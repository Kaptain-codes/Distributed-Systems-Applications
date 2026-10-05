/* ============================================================
   CONFIG / STATE
   ============================================================ */
const KEYS=["fd.customerId","fd.addressId","fd.address","fd.autoRegister","fd.baseUrl","fd.pollMs","fd.activeOrderId","fd.drivers","fd.useIdempotencyKey"];
const defaultBase="http://localhost:9090/api";
const state={tab:"catalog",restaurants:[],menus:[],selectedRestaurant:null,orders:[],order:null,payment:null,delivery:null,notifications:[],addresses:[],qty:1,selectedItem:null,drivers:[],requestLog:[],events:[],pollTimer:null,lastSnapshot:null,errorRetry:null,simRestaurant:null};
const $=id=>document.getElementById(id);
const get=(key,fallback)=>localStorage.getItem(`fd.${key}`)??fallback;
const set=(key,value)=>value===null?localStorage.removeItem(`fd.${key}`):localStorage.setItem(`fd.${key}`,typeof value==="string"?value:JSON.stringify(value));
const parse=(key,fallback)=>{const raw=get(key,null);if(raw===null)return fallback;try{return JSON.parse(raw)}catch{return raw}};
function setState(patch){Object.assign(state,patch);queueMicrotask(render);}
function text(value,fallback="—"){return value===undefined||value===null||value===""?fallback:String(value)}
function formatMoney(value,currency="NAD"){const n=Number(value);return Number.isFinite(n)?`${currency} ${n.toFixed(2)}`:"NAD —"}
function formatTime(value){if(!value)return"—";const date=new Date(value);return Number.isNaN(date.valueOf())?"—":date.toLocaleString()}
function idOf(value){return String(value)}

/* ============================================================
   API
   ============================================================ */
function baseUrl(){return String($("baseUrl").value||get("baseUrl",defaultBase)).replace(/\/+$/,"")}
function logRequest(entry){state.requestLog=[entry,...state.requestLog].slice(0,50);renderDebug()}
async function apiFetch(method,path,opts={}){
  const url=baseUrl()+path;const started=performance.now();const headers={Accept:"application/json",...(opts.headers||{})};
  if(opts.body!==undefined)headers["Content-Type"]="application/json";
  if((method==="POST"&&(/^\/order\/orders$/.test(path)||/^\/order\/orders\/[^/]+\/cancel$/.test(path)))&&get("useIdempotencyKey","false")==="true")headers["Idempotency-Key"]=crypto.randomUUID();
  let response;let body;
  try{response=await fetch(url,{method,headers,body:opts.body===undefined?undefined:JSON.stringify(opts.body)});const raw=await response.text();try{body=raw?JSON.parse(raw):null}catch{body=raw}}
  catch(error){logRequest({method,url,status:"network",ms:Math.round(performance.now()-started)});showBanner(`Cannot reach ${url}. Likely: gateway down, CORS, or wrong base URL.`);throw error}
  logRequest({method,url,status:response.status,ms:Math.round(performance.now()-started),request:opts.body,response:body});
  if(!response.ok){const failure={status:response.status,error:body?.error||"HTTP_ERROR",message:body?.message||`HTTP ${response.status}`,url,body};throw failure}
  return body
}
function write(method,path,body,opts={}){console.debug(`${method} ${baseUrl()+path}`,body);return apiFetch(method,path,{...opts,body})}
function showBanner(message){$("banner").textContent=message;$("banner").hidden=false}
function clearBanner(){$("banner").hidden=true}
function notify(message,variant="ok"){const node=el("div",{className:`toast ${variant}`},[message]);const close=el("button",{textContent:"×",title:"Dismiss"});close.onclick=()=>node.remove();node.append(close);$("toastStack").append(node);setTimeout(()=>node.remove(),5000)}
function apiMessage(error){if(error.status===409)return`Invalid state: ${text(error.message)}`;if(error.status===404)return`Not found: ${error.url}`;if(error.status===502||error.status===503)return"Upstream unavailable. No changes were made.";if(error.status===400)return text(error.message);return text(error.message,"Request failed")}

/* ============================================================
   IDENTITY
   ============================================================ */
function readId(resp,...candidateKeys){
  for(const location of [resp,resp?.data,resp?.body])for(const key of candidateKeys){const value=location?.[key];if(typeof value==="string"||typeof value==="number")return String(value)}
  console.error("Unable to read id",resp,candidateKeys);return null
}
function buildRegisterCustomerPayload(){return{name:"Demo Customer",email:`demo+${Date.now()}@example.com`,phone:"+264810000000"}}
function buildAddressPayload(){return{label:"Home",line1:"1 Demo Street",city:"Windhoek",region:"Khomas",is_default:true}}
function buildRegisterDriverPayload(data){return{name:data.name,phone:data.phone}}
function contractError(succeeded,raw,candidates,retry){state.errorRetry=retry;$("errorSummary").textContent=`${succeeded}. Candidate keys searched: ${candidates.join(", ")}`;$("errorRaw").textContent=JSON.stringify(raw,null,2);$("errorSheet").hidden=false}
async function resolveIdentity(){
  const query=new URLSearchParams(location.search);const queryId=query.get("customerId");if(queryId){set("customerId",queryId);return validateCustomer(queryId)}
  const stored=get("customerId",null);if(stored)return validateCustomer(stored);
  if(get("autoRegister","true")!=="true"){contractError("A customerId is required",{},["id","customerId","_id"],resolveIdentity);return}
  try{const response=await write("POST","/customer/customers",buildRegisterCustomerPayload());const customerId=readId(response,"id","customerId","_id");if(!customerId){contractError("Customer registration succeeded but no customer id was returned",response,["id","customerId","_id"],resolveIdentity);return}set("customerId",customerId);try{const addressResponse=await write("POST",`/customer/customers/${encodeURIComponent(customerId)}/addresses`,buildAddressPayload());const addressId=readId(addressResponse,"id","addressId","_id");if(!addressId){set("addressId",null);set("address",null);contractError("Customer succeeded; address response had no address id",addressResponse,["id","addressId","_id"],()=>registerAddress(customerId));return}set("addressId",addressId);set("address",addressResponse)}catch(error){set("addressId",null);set("address",null);contractError(`Customer created, but address registration failed: ${apiMessage(error)}`,error.body||error,["id","addressId","_id"],()=>registerAddress(customerId))}await validateCustomer(customerId)}catch(error){notify(apiMessage(error),"err")}
}
async function registerAddress(customerId){try{const response=await write("POST",`/customer/customers/${encodeURIComponent(customerId)}/addresses`,buildAddressPayload());const addressId=readId(response,"id","addressId","_id");if(!addressId){contractError("Address registration succeeded but no address id was returned",response,["id","addressId","_id"],()=>registerAddress(customerId));return}set("addressId",addressId);set("address",response);$("errorSheet").hidden=true;await validateCustomer(customerId)}catch(error){notify(apiMessage(error),"err")}}
async function validateCustomer(customerId){try{await apiFetch("GET",`/customer/customers/${encodeURIComponent(customerId)}`);set("customerId",customerId);$("customerLine").textContent=`Customer ${customerId.slice(0,8)}… · connected`;await loadAddresses()}catch(error){if(error.status===404){set("customerId",null);set("addressId",null);set("address",null);return resolveIdentity()}showBanner(`Cannot validate customer at ${error.url||baseUrl()}.`);throw error}}
function customerPanel(){const panel=el("div",{className:"banner"});panel.append(el("strong",{textContent:`Customer ${text(get("customerId","—"))}`}));const copy=el("button",{textContent:"Copy id"});copy.onclick=()=>navigator.clipboard?.writeText(get("customerId",""));const other=el("button",{textContent:"Use a different id"});other.onclick=()=>{const id=prompt("Enter server-generated customerId");if(id){set("customerId",id);validateCustomer(id)}};const fresh=el("button",{textContent:"Register demo customer"});fresh.onclick=()=>{set("customerId",null);set("addressId",null);set("address",null);resolveIdentity()};panel.append(copy,other,fresh);$("banner").replaceChildren(panel);$("banner").hidden=false}

/* ============================================================
   POLLING
   ============================================================ */
async function poll(){
  const active=get("activeOrderId",null),customerId=get("customerId",null);if(!active&&!customerId)return;
  const paths=[active?`/order/orders/${encodeURIComponent(active)}`:null,active?`/payment/payments/${encodeURIComponent(active)}`:null,active?`/delivery/deliveries/${encodeURIComponent(active)}`:null,customerId?`/notification/notifications?recipientId=${encodeURIComponent(customerId)}`:null];
  const results=await Promise.allSettled(paths.map(path=>path?apiFetch("GET",path):Promise.reject({status:404})));
  const [order,payment,delivery,notifications]=results.map(result=>result.status==="fulfilled"?result.value:null);
  if(order){diff(order,"order");setState({order})}if(payment){diff(payment,"payment");setState({payment})}if(delivery){diff(delivery,"delivery");setState({delivery})}if(notifications){diff(notifications,"notification");setState({notifications:Array.isArray(notifications)?notifications:Object.values(notifications||{})})}
  renderTrack();renderNotifications();updateStats();
  const terminal=order?.status==="DELIVERED"||order?.status==="CANCELLED";schedulePoll(terminal?15000:(state.tab==="track"?Number(get("pollMs",2000)):10000))
}
function schedulePoll(ms){clearTimeout(state.pollTimer);state.pollTimer=setTimeout(poll,ms)}
function diff(value,source){const previous=state.lastSnapshot?.[source];if(source==="order"&&previous){const oldHistory=previous.statusHistory||[];for(const item of (value.statusHistory||[]).slice(oldHistory.length))state.events.push({at:item.at||new Date().toISOString(),source,description:`${text(item.from)} → ${text(item.to)}${item.reason?` · ${item.reason}`:""}`,key:item.eventId||`${item.at}+`}) ;if(previous.paymentStatus!==value.paymentStatus)state.events.push({at:new Date().toISOString(),source,description:`Payment is now ${text(value.paymentStatus)}`});if(previous.driverId!==value.driverId)state.events.push({at:new Date().toISOString(),source,description:`Driver changed to ${text(value.driverId)}`})}if(source==="payment"&&previous&&previous.status!==value.status)state.events.push({at:new Date().toISOString(),source,description:`Payment is now ${text(value.status)}`});if(source==="delivery"&&previous&&previous.status!==value.status)state.events.push({at:new Date().toISOString(),source,description:`Delivery is now ${text(value.status)}`});state.lastSnapshot={...(state.lastSnapshot||{}),[source]:value};state.events=state.events.slice(-50)}

/* ============================================================
   CATALOG
   ============================================================ */
async function loadAddresses(){const id=get("customerId",null);if(!id)return;try{const addresses=await apiFetch("GET",`/customer/customers/${encodeURIComponent(id)}/addresses`);setState({addresses:Array.isArray(addresses)?addresses:[]})}catch(error){notify(apiMessage(error),"err")}}
async function loadCatalog(){try{const restaurants=await apiFetch("GET","/restaurant/restaurants");setState({restaurants:Array.isArray(restaurants)?restaurants:[]});renderCatalog();for(const restaurant of state.restaurants){try{const menu=await apiFetch("GET",`/restaurant/restaurants/${encodeURIComponent(readId(restaurant,"id","restaurantId","_id")||"")}/menu`);state.menus.push(...(Array.isArray(menu)?menu:[]));renderCatalog()}catch(error){notify(`Menu unavailable: ${apiMessage(error)}`,"warn")}}}catch(error){notify(apiMessage(error),"err")}}
function buildPlaceOrderPayload({customerId,restaurantId,address,items,paymentMethod}){return{customerId,restaurantId,addressId:readId(address,"id","addressId","_id")||get("addressId",null),deliveryAddress:address,items:items.map(item=>({menuItemId:readId(item,"menuItemId","id","_id"),qty:item.qty})),paymentMethod}}
function openOrderSheet(item){setState({selectedItem:item,qty:1});$("orderSheet").hidden=false;renderSheet();loadAddresses()}
async function placeOrder(){const item=state.selectedItem,address=state.addresses.find(item=>idOf(item.id??item.addressId)===get("addressId",""))||parse("address",null);if(!item||!address){$("sheetMessage").textContent="A delivery address is required.";return}const button=$("placeOrderBtn");button.disabled=true;try{const response=await write("POST","/order/orders",buildPlaceOrderPayload({customerId:get("customerId",""),restaurantId:item.restaurantId,address,items:[{...item,qty:state.qty}],paymentMethod:document.querySelector('input[name="payment"]:checked').value}));const orderId=readId(response,"id","orderId","_id");if(!orderId){contractError("Order succeeded but no order id was returned",response,["id","orderId","_id"],placeOrder);return}set("activeOrderId",orderId);$("orderSheet").hidden=true;switchTab("track");notify("Order placed. Tracking started.");poll()}catch(error){if(error.status===502||error.status===503)notify("No order was created — a dependency is unavailable.","warn");else $("sheetMessage").textContent=apiMessage(error)}finally{button.disabled=false}}

/* ============================================================
   TRACK
   ============================================================ */
const states=["CREATED","CONFIRMED","PREPARING","READY","OUT_FOR_DELIVERY","DELIVERED"];
function orderId(order){return readId(order,"_id","id","orderId")}
async function loadOrder(id){try{const order=await apiFetch("GET",`/order/orders/${encodeURIComponent(id)}`);setState({order});renderTrack();poll()}catch(error){notify(apiMessage(error),"err")}}
async function cancelTracked(){if(!state.order)return;try{await write("POST",`/order/orders/${encodeURIComponent(orderId(state.order))}/cancel`);await loadOrder(orderId(state.order))}catch(error){notify(error.status===409?`Too late to cancel — the order is already ${text(state.order.status)}.`:apiMessage(error),"warn")}}
function renderTrack(){const order=state.order;const root=$("trackView");root.replaceChildren();if(!order){root.append(el("p",{className:"empty",textContent:"Choose an order to begin tracking."}));return}const oid=orderId(order);const head=el("div",{className:"asset-card"},[el("strong",{textContent:oid||"—"}),el("span",{textContent:formatMoney(order.total,order.currency)}),badge(order.status),badge(order.paymentStatus,"payment")]);root.append(head);if(order.status==="CANCELLED")root.append(el("div",{className:"banner",textContent:`Cancelled: ${text(order.cancellationType)} — ${text(order.cancellationReason)}`}));const stepper=el("div",{className:"stepper"});const current=states.indexOf(order.status);states.forEach((name,index)=>{const cls=order.status==="CANCELLED"&&index>current?"upcoming":index<current?"done":index===current?"current":"upcoming";const node=el("div",{className:`step ${cls}`,textContent:name==="READY"?"Finding a driver":name==="OUT_FOR_DELIVERY"?"On the way":name});if(cls==="current")node.setAttribute("aria-current","step");stepper.append(node)});root.append(stepper);root.append(el("h3",{textContent:"Timeline"}));const timeline=el("div",{className:"timeline"});for(const event of order.statusHistory||[])timeline.append(el("div",{className:"timeline-row",textContent:`${text(event.from)} → ${text(event.to)} · ${formatTime(event.at)}${event.reason?` · ${event.reason}`:""}`}));root.append(timeline);root.append(el("h3",{textContent:"Observed events (inferred from API polling — not a Kafka consumer)."}));const feed=el("div",{className:"feed"});for(const event of state.events)feed.append(el("div",{className:"feed-row",textContent:`${formatTime(event.at)} · ${event.source} · ${event.description}`}));root.append(feed);const actions=el("div",{className:"actions"});const cancel=el("button",{textContent:"Cancel order"});cancel.disabled=!["CREATED","CONFIRMED"].includes(order.status);cancel.onclick=cancelTracked;actions.append(cancel);const auto=el("button",{textContent:"Auto-drive this order"});auto.onclick=()=>{$("autoDrive").checked=true;autoDrive()};actions.append(auto);root.append(actions)}
function badge(value,prefix=""){return el("span",{className:`badge ${prefix?`${prefix}-${String(value||"").toLowerCase()}`:String(value||"").toLowerCase()}`,textContent:text(value)})}

/* ============================================================
   SIMULATOR
   ============================================================ */
function buildRejectOrderPayload(reason){return{reason}}function buildFailDeliveryPayload(reason){return{reason}}function buildDriverStatusPayload(status){return{status}}
async function kitchenAction(orderId,action,body){try{await write("POST",`/restaurant/orders/${encodeURIComponent(orderId)}/${action}`,body);notify(`Order ${action} completed`);poll()}catch(error){notify(apiMessage(error),"err")}}
async function registerDriver(){const name=prompt("Driver name");const phone=prompt("Driver phone");if(!name||!phone)return;try{const response=await write("POST","/delivery/drivers",buildRegisterDriverPayload({name,phone}));const driverId=readId(response,"id","driverId","_id");if(!driverId){contractError("Driver registration succeeded but no driver id was returned",response,["id","driverId","_id"],registerDriver);return}const drivers=[...state.drivers,{id:driverId,name,phone}];set("drivers",drivers);setState({drivers});renderDrivers()}catch(error){notify(apiMessage(error),"err")}}
async function driverAction(action){const selected=state.drivers.find(driver=>driver.selected);const oid=state.order&&orderId(state.order);if(!selected||!oid){notify("Select a driver and track an order first.","warn");return}try{await write("POST",`/delivery/deliveries/${encodeURIComponent(oid)}/${action}`,action==="fail"?buildFailDeliveryPayload("Driver simulation failure"):undefined,{headers:{"X-Driver-Id":selected.id}});notify(`Delivery ${action} completed`);poll()}catch(error){notify(apiMessage(error),"err")}}
function autoDrive(){const oid=state.order&&orderId(state.order);if(!oid)return;const actions=[["accept",0],["preparing",3000],["ready",6000],["pickup",9000],["complete",13000]];for(const [action,delay] of actions)setTimeout(async()=>{if(state.order&&orderId(state.order)===oid&&!["DELIVERED","CANCELLED"].includes(state.order.status)){if(action==="pickup"||action==="complete")await driverAction(action);else await kitchenAction(oid,action)}},delay)}
async function loadKitchen(){
  const rid=$("simRestaurant").value;if(!rid)return;
  try{
    const rows=await apiFetch("GET",`/restaurant/restaurants/${encodeURIComponent(rid)}/orders?status=PENDING_DECISION`);
    const nodes=(Array.isArray(rows)?rows:[]).map(row=>{
      const oid=readId(row,"id","orderId","_id");
      const node=el("div",{className:"kitchen-row"},[
        el("strong",{textContent:oid||"—"}),
        el("span",{textContent:` ${text(row.status)}`})
      ]);
      const accept=el("button",{textContent:"Accept"});
      accept.onclick=()=>kitchenAction(oid,"accept");
      const reject=el("button",{textContent:"Reject"});
      reject.onclick=()=>kitchenAction(oid,"reject",buildRejectOrderPayload("DECLINED"));
      node.append(accept,reject);return node;
    });
    $("kitchenList").replaceChildren(...nodes);
  }catch(error){notify(apiMessage(error),"warn")}
}
function renderDrivers(){
  const root=$("driverRoster");
  const nodes=state.drivers.map(driver=>{
    const card=el("div",{className:"driver-card"},[
      el("strong",{textContent:text(driver.name)}),
      el("span",{className:"meta",textContent:` ${driver.id}`})
    ]);
    const select=el("button",{textContent:driver.selected?"Selected":"Select"});
    select.onclick=()=>{state.drivers.forEach(item=>item.selected=false);driver.selected=true;renderDrivers()};
    const status=el("button",{textContent:"Set available"});
    status.onclick=()=>setDriverStatus(driver,"AVAILABLE");
    card.append(select,status);return card;
  });
  root.replaceChildren(...nodes);
}
async function setDriverStatus(driver,status){try{await write("PUT",`/delivery/drivers/${encodeURIComponent(driver.id)}/status`,buildDriverStatusPayload(status));notify("Driver status updated")}catch(error){if(error.status===404){const drivers=state.drivers.filter(item=>item.id!==driver.id);set("drivers",drivers);setState({drivers});notify("Cached driver was not found; register it again.","warn")}else notify(apiMessage(error),"err")}}

/* ============================================================
   RENDER HELPERS
   ============================================================ */
function el(tag,props={},children=[]){const node=document.createElement(tag);for(const [key,value] of Object.entries(props)){if(key==="className")node.className=value;else if(key==="textContent")node.textContent=value;else if(key.startsWith("on"))node.addEventListener(key.slice(2),value);else node.setAttribute(key,value)}node.append(...children);return node}
function renderCatalog(){const restaurantRoot=$("restaurantList");restaurantRoot.replaceChildren(...state.restaurants.map(restaurant=>{const id=readId(restaurant,"id","restaurantId","_id");const card=el("button",{className:"asset-card",type:"button"},[el("strong",{textContent:text(restaurant.name)}),el("span",{textContent:text(restaurant.address)}),el("span",{textContent:restaurant.active===false?"Closed":"Open"})]);card.onclick=()=>{setState({selectedRestaurant:id});renderCatalog()};return card}));const sim=$("simRestaurant");const previous=sim.value;sim.replaceChildren(...state.restaurants.map(restaurant=>{const id=readId(restaurant,"id","restaurantId","_id");return el("option",{value:id,textContent:text(restaurant.name)})}));if(previous)sim.value=previous;const menuRoot=$("menuList");const query=$("menuSearch").value.toLowerCase();const items=state.menus.filter(item=>(!state.selectedRestaurant||idOf(item.restaurantId)===state.selectedRestaurant)&&`${item.name||""}`.toLowerCase().includes(query));menuRoot.replaceChildren(...items.map(item=>{const available=item.available!==false&&Number(item.stockQty??item.stock_qty??0)>0;const card=el("div",{className:`asset-card ${available?"clickable":""}`},[el("strong",{textContent:text(item.name)}),el("span",{textContent:formatMoney(item.unitPrice)}),el("span",{text:`Stock ${text(item.stockQty??item.stock_qty,"0")}`}),badge(available?"Available":"Unavailable")]);if(available)card.onclick=()=>openOrderSheet(item);return card}))}
function renderSheet(){$("sheetTitle").textContent=text(state.selectedItem?.name);$("sheetPrice").textContent=formatMoney(state.selectedItem?.unitPrice);$("qtyValue").textContent=state.qty;$("sheetTotal").textContent=`Total preview: ${formatMoney(Number(state.selectedItem?.unitPrice||0)*state.qty)}`;const select=$("addressSelect");select.replaceChildren(...state.addresses.map(address=>{const id=readId(address,"id","addressId","_id");const option=el("option",{value:id,textContent:`${text(address.label,"Address")} — ${text(address.line1)}`});option.selected=id===get("addressId","");return option}))}
async function loadOrders(){const id=get("customerId",null);if(!id)return;try{const orders=await apiFetch("GET",`/order/orders?customerId=${encodeURIComponent(id)}`);setState({orders:Array.isArray(orders)?orders:Object.values(orders||{})});renderOrders()}catch(error){notify(apiMessage(error),"err")}}
function renderOrders(){const root=$("ordersList");root.replaceChildren(...state.orders.sort((a,b)=>String(b.createdAt).localeCompare(String(a.createdAt))).map(order=>{const card=el("button",{className:"asset-card",type:"button"},[el("strong",{textContent:orderId(order)||"—"}),el("span",{textContent:formatMoney(order.total,order.currency)}),badge(order.status)]);card.onclick=()=>{set("activeOrderId",orderId(order));setState({order});switchTab("track");poll()};return card}));if(!state.orders.length)root.append(el("p",{className:"empty",textContent:"No orders yet — browse the catalog."}))}
function renderNotifications(){const root=$("notificationsList");root.replaceChildren(...state.notifications.map(notification=>{const id=readId(notification,"id","notificationId","_id");const card=el("div",{className:"asset-card"},[el("strong",{textContent:text(notification.type)}),el("p",{textContent:text(notification.message)}),el("span",{className:"meta",textContent:`${text(notification.channel)} · ${formatTime(notification.createdAt)}`}),el("span",{className:"badge",textContent:notification.readAt?"Read":"Unread"})]);if(!notification.readAt){const read=el("button",{textContent:"Mark read"});read.onclick=async()=>{try{await write("PUT",`/notification/notifications/${encodeURIComponent(id)}/read`);poll()}catch(error){notify(apiMessage(error),"err")}};card.append(read)}return card}));updateStats()}
function updateStats(){const active=state.orders.filter(order=>!["DELIVERED","CANCELLED"].includes(order.status)).length;const today=new Date().toDateString();$("cartStat").textContent="0";$("activeStat").textContent=active;$("deliveredStat").textContent=state.orders.filter(order=>order.status==="DELIVERED"&&new Date(order.updatedAt).toDateString()===today).length;const unread=state.notifications.filter(item=>!item.readAt).length;$("unreadStat").textContent=unread;$("unreadBadge").textContent=unread||""}
function renderDebug(){$("debugLog").textContent=state.requestLog.map(item=>`${item.method} ${item.url} -> ${item.status} (${item.ms}ms)`).join("\n")}
function render(){renderCatalog();renderOrders();renderTrack();renderNotifications();renderDrivers();updateStats();renderDebug()}
function switchTab(tab){state.tab=tab;document.querySelectorAll(".tab").forEach(button=>button.classList.toggle("active",button.dataset.tab===tab));document.querySelectorAll(".panel").forEach(panel=>panel.classList.toggle("active",panel.id===`panel-${tab}`));location.hash=`tab=${tab}`;if(tab==="track")poll();if(tab==="orders")loadOrders();if(tab==="notifications")poll()}

/* ============================================================
   BOOT
   ============================================================ */
function bind(){document.querySelectorAll(".tab").forEach(button=>button.onclick=()=>switchTab(button.dataset.tab));$("connectBtn").onclick=()=>{set("baseUrl",$("baseUrl").value);clearBanner();boot()};$("customerChip").onclick=customerPanel;$("allRestaurants").onclick=()=>setState({selectedRestaurant:null});$("menuSearch").oninput=renderCatalog;$("reloadOrders").onclick=loadOrders;$("reloadNotifications").onclick=poll;$("closeSheet").onclick=()=>$("orderSheet").hidden=true;$("placeOrderBtn").onclick=placeOrder;$("qtyDown").onclick=()=>{setState({qty:Math.max(1,state.qty-1)});renderSheet()};$("qtyUp").onclick=()=>{setState({qty:Math.min(Number(state.selectedItem?.stockQty||1),state.qty+1)});renderSheet()};$("openSimulator").onclick=()=>switchTab("simulator");$("registerDriver").onclick=registerDriver;$("pickupBtn").onclick=()=>driverAction("pickup");$("completeBtn").onclick=()=>driverAction("complete");$("failBtn").onclick=()=>driverAction("fail");$("markPreparing").onclick=()=>state.order&&kitchenAction(orderId(state.order),"preparing");$("markReady").onclick=()=>state.order&&kitchenAction(orderId(state.order),"ready");$("simRestaurant").onchange=loadKitchen;$("autoDrive").onchange=()=>{if($("autoDrive").checked)autoDrive()};$("retryError").onclick=()=>{const retry=state.errorRetry;$("errorSheet").hidden=true;retry?.()};$("cancelError").onclick=()=>$("errorSheet").hidden=true;$("copyError").onclick=()=>navigator.clipboard?.writeText($("errorRaw").textContent);$("settingsForm").onsubmit=event=>{event.preventDefault();set("baseUrl",$("settingsBaseUrl").value);set("customerId",$("settingsCustomerId").value||null);set("pollMs",Number($("settingsPollMs").value));set("autoRegister",$("settingsAutoRegister").checked?"true":"false");set("useIdempotencyKey",$("settingsIdempotency").checked?"true":"false");$("baseUrl").value=get("baseUrl",defaultBase);notify("Settings saved");boot()};$("resetState").onclick=()=>{KEYS.forEach(key=>localStorage.removeItem(key));location.reload()};window.addEventListener("keydown",event=>{if(event.key==="Escape")$("orderSheet").hidden=true});window.addEventListener("hashchange",()=>{const tab=new URLSearchParams(location.hash.slice(1)).get("tab");if(tab)switchTab(tab)});renderDrivers()}
async function boot(){clearBanner();$("baseUrl").value=get("baseUrl",defaultBase);$("settingsBaseUrl").value=get("baseUrl",defaultBase);$("settingsCustomerId").value=get("customerId","");$("settingsPollMs").value=get("pollMs",2000);$("settingsAutoRegister").checked=get("autoRegister","true")==="true";$("settingsIdempotency").checked=get("useIdempotencyKey","false")==="true";const hash=new URLSearchParams(location.hash.slice(1));const deepOrder=hash.get("track");if(deepOrder){set("activeOrderId",deepOrder);switchTab("track")}try{await resolveIdentity();await loadCatalog();await loadOrders();await poll();$("connDot").classList.add("connected");$("connectionState").textContent="Connected"}catch(error){$("connDot").classList.remove("connected");$("connectionState").textContent="Unreachable"}}
bind();boot();
