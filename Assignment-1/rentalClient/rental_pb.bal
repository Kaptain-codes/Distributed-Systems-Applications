import ballerina/grpc;
import ballerina/protobuf;

public const string RENTAL_DESC = "0A0C72656E74616C2E70726F746F120672656E74616C229A020A0850726F7065727479121E0A0A70726F70657274794964180120012809520A70726F7065727479496412160A06686F737449641802200128095206686F7374496412120A046E616D6518032001280952046E616D65121A0A086C6F636174696F6E18042001280952086C6F636174696F6E12160A06726567696F6E1805200128095206726567696F6E12380A0C70726F70657274795479706518062001280E32142E72656E74616C2E50726F706572747954797065520C70726F70657274795479706512240A0D70726963655065724E69676874180720012801520D70726963655065724E69676874122E0A0673746174757318082001280E32162E72656E74616C2E50726F70657274795374617475735206737461747573226E0A045573657212160A06757365724964180120012809520675736572496412120A046E616D6518022001280952046E616D6512140A05656D61696C1803200128095205656D61696C12240A04726F6C6518042001280E32102E72656E74616C2E55736572526F6C655204726F6C6522CD010A07426F6F6B696E67121C0A09626F6F6B696E6749641801200128095209626F6F6B696E674964121E0A0A70726F70657274794964180220012809520A70726F7065727479496412180A076775657374496418032001280952076775657374496412180A07636865636B496E1804200128095207636865636B496E121A0A08636865636B4F75741805200128095208636865636B4F7574121C0A09746F74616C436F73741806200128015209746F74616C436F737412160A066E696768747318072001280552066E69676874732284020A1241646450726F70657274795265717565737412160A06686F737449641801200128095206686F7374496412120A046E616D6518022001280952046E616D65121A0A086C6F636174696F6E18032001280952086C6F636174696F6E12160A06726567696F6E1804200128095206726567696F6E12380A0C70726F70657274795479706518052001280E32142E72656E74616C2E50726F706572747954797065520C70726F70657274795479706512240A0D70726963655065724E69676874180620012801520D70726963655065724E69676874122E0A0673746174757318072001280E32162E72656E74616C2E50726F7065727479537461747573520673746174757322690A1341646450726F7065727479526573706F6E736512180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D657373616765121E0A0A70726F70657274794964180320012809520A70726F7065727479496422430A11557365724372656174696F6E4572726F7212160A06757365724964180120012809520675736572496412160A06726561736F6E1802200128095206726561736F6E22EA010A134372656174655573657273526573706F6E736512180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D65737361676512220A0C63726561746564436F756E74180320012805520C63726561746564436F756E7412260A0E6372656174656455736572496473180420032809520E637265617465645573657249647312200A0B6661696C6564436F756E74180520012805520B6661696C6564436F756E7412310A066572726F727318062003280B32192E72656E74616C2E557365724372656174696F6E4572726F7252066572726F727322EC020A1555706461746550726F706572747952657175657374121E0A0A70726F70657274794964180120012809520A70726F7065727479496412160A06686F737449641802200128095206686F7374496412170A046E616D65180320012809480052046E616D65880101121F0A086C6F636174696F6E180420012809480152086C6F636174696F6E88010112290A0D70726963655065724E696768741805200128014802520D70726963655065724E6967687488010112330A0673746174757318062001280E32162E72656E74616C2E50726F706572747953746174757348035206737461747573880101123D0A0C70726F70657274795479706518072001280E32142E72656E74616C2E50726F7065727479547970654804520C70726F70657274795479706588010142070A055F6E616D65420B0A095F6C6F636174696F6E42100A0E5F70726963655065724E6967687442090A075F737461747573420F0A0D5F70726F706572747954797065227A0A1655706461746550726F7065727479526573706F6E736512180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D657373616765122C0A0870726F706572747918032001280B32102E72656E74616C2E50726F7065727479520870726F7065727479224F0A1552656D6F766550726F706572747952657175657374121E0A0A70726F70657274794964180120012809520A70726F7065727479496412160A06686F737449641802200128095206686F7374496422AC010A1652656D6F766550726F7065727479526573706F6E736512180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D65737361676512160A06726567696F6E1803200128095206726567696F6E12300A0A70726F7065727469657318042003280B32102E72656E74616C2E50726F7065727479520A70726F7065727469657312140A05636F756E741805200128055205636F756E7422AA010A1E4C697374417661696C61626C6550726F7065727469657352657175657374121F0A086C6F636174696F6E180120012809480052086C6F636174696F6E880101121F0A086D696E5072696365180220012801480152086D696E5072696365880101121F0A086D61785072696365180320012801480252086D61785072696365880101420B0A095F6C6F636174696F6E420B0A095F6D696E5072696365420B0A095F6D6178507269636522370A1553656172636850726F706572747952657175657374121E0A0A70726F70657274794964180120012809520A70726F70657274794964228C010A1653656172636850726F7065727479526573706F6E736512180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D65737361676512310A0870726F706572747918032001280B32102E72656E74616C2E50726F70657274794800520870726F7065727479880101420B0A095F70726F70657274792285010A13426F6F6B50726F70657274795265717565737412180A0767756573744964180120012809520767756573744964121E0A0A70726F70657274794964180220012809520A70726F7065727479496412180A07636865636B496E1803200128095207636865636B496E121A0A08636865636B4F75741804200128095208636865636B4F757422A8010A14426F6F6B50726F7065727479526573706F6E736512180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D657373616765121E0A0A636172744974656D4964180320012809520A636172744974656D496412160A066E696768747318042001280552066E696768747312240A0D657374696D61746564436F7374180520012801520D657374696D61746564436F737422510A15436F6E6669726D426F6F6B696E675265717565737412180A0767756573744964180120012809520767756573744964121E0A0A636172744974656D4964180220012809520A636172744974656D49642288010A16436F6E6669726D426F6F6B696E67526573706F6E736512180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D657373616765122E0A07626F6F6B696E6718032001280B320F2E72656E74616C2E426F6F6B696E6748005207626F6F6B696E67880101420A0A085F626F6F6B696E672A620A0E50726F7065727479537461747573121F0A1B50524F50455254595F5354415455535F554E5350454349464945441000120D0A09415641494C41424C451001120F0A0B554E415641494C41424C451002120F0A0B4D41494E54454E414E434510032A3A0A0855736572526F6C6512190A15555345525F524F4C455F554E535045434946494544100012080A04484F5354100112090A05475545535410022A7E0A0C50726F706572747954797065121D0A1950524F50455254595F545950455F554E5350454349464945441000120D0A0941504152544D454E54100112090A05484F5553451002120B0A07434F5454414745100312090A054C4F4447451004120F0A0B47554553545F484F5553451005120C0A0843414D5053495445100632F9040A0D52656E74616C5365727669636512460A0B41646450726F7065727479121A2E72656E74616C2E41646450726F7065727479526571756573741A1B2E72656E74616C2E41646450726F7065727479526573706F6E7365124F0A0E55706461746550726F7065727479121D2E72656E74616C2E55706461746550726F7065727479526571756573741A1E2E72656E74616C2E55706461746550726F7065727479526573706F6E7365124F0A0E52656D6F766550726F7065727479121D2E72656E74616C2E52656D6F766550726F7065727479526571756573741A1E2E72656E74616C2E52656D6F766550726F7065727479526573706F6E7365123A0A0B4372656174655573657273120C2E72656E74616C2E557365721A1B2E72656E74616C2E4372656174655573657273526573706F6E7365280112550A174C697374417661696C61626C6550726F7065727469657312262E72656E74616C2E4C697374417661696C61626C6550726F70657274696573526571756573741A102E72656E74616C2E50726F70657274793001124F0A0E53656172636850726F7065727479121D2E72656E74616C2E53656172636850726F7065727479526571756573741A1E2E72656E74616C2E53656172636850726F7065727479526573706F6E736512490A0C426F6F6B50726F7065727479121B2E72656E74616C2E426F6F6B50726F7065727479526571756573741A1C2E72656E74616C2E426F6F6B50726F7065727479526573706F6E7365124F0A0E436F6E6669726D426F6F6B696E67121D2E72656E74616C2E436F6E6669726D426F6F6B696E67526571756573741A1E2E72656E74616C2E436F6E6669726D426F6F6B696E67526573706F6E7365620670726F746F33";

public isolated client class RentalServiceClient {
    *grpc:AbstractClientEndpoint;

    private final grpc:Client grpcClient;

    public isolated function init(string url, *grpc:ClientConfiguration config) returns grpc:Error? {
        self.grpcClient = check new (url, config);
        check self.grpcClient.initStub(self, RENTAL_DESC);
    }

    isolated remote function AddProperty(AddPropertyRequest|ContextAddPropertyRequest req) returns AddPropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        AddPropertyRequest message;
        if req is ContextAddPropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("rental.RentalService/AddProperty", message, headers);
        [anydata, map<string|string[]>] [result, _] = payload;
        return <AddPropertyResponse>result;
    }

    isolated remote function AddPropertyContext(AddPropertyRequest|ContextAddPropertyRequest req) returns ContextAddPropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        AddPropertyRequest message;
        if req is ContextAddPropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("rental.RentalService/AddProperty", message, headers);
        [anydata, map<string|string[]>] [result, respHeaders] = payload;
        return {content: <AddPropertyResponse>result, headers: respHeaders};
    }

    isolated remote function UpdateProperty(UpdatePropertyRequest|ContextUpdatePropertyRequest req) returns UpdatePropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        UpdatePropertyRequest message;
        if req is ContextUpdatePropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("rental.RentalService/UpdateProperty", message, headers);
        [anydata, map<string|string[]>] [result, _] = payload;
        return <UpdatePropertyResponse>result;
    }

    isolated remote function UpdatePropertyContext(UpdatePropertyRequest|ContextUpdatePropertyRequest req) returns ContextUpdatePropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        UpdatePropertyRequest message;
        if req is ContextUpdatePropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("rental.RentalService/UpdateProperty", message, headers);
        [anydata, map<string|string[]>] [result, respHeaders] = payload;
        return {content: <UpdatePropertyResponse>result, headers: respHeaders};
    }

    isolated remote function RemoveProperty(RemovePropertyRequest|ContextRemovePropertyRequest req) returns RemovePropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        RemovePropertyRequest message;
        if req is ContextRemovePropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("rental.RentalService/RemoveProperty", message, headers);
        [anydata, map<string|string[]>] [result, _] = payload;
        return <RemovePropertyResponse>result;
    }

    isolated remote function RemovePropertyContext(RemovePropertyRequest|ContextRemovePropertyRequest req) returns ContextRemovePropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        RemovePropertyRequest message;
        if req is ContextRemovePropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("rental.RentalService/RemoveProperty", message, headers);
        [anydata, map<string|string[]>] [result, respHeaders] = payload;
        return {content: <RemovePropertyResponse>result, headers: respHeaders};
    }

    isolated remote function SearchProperty(SearchPropertyRequest|ContextSearchPropertyRequest req) returns SearchPropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        SearchPropertyRequest message;
        if req is ContextSearchPropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("rental.RentalService/SearchProperty", message, headers);
        [anydata, map<string|string[]>] [result, _] = payload;
        return <SearchPropertyResponse>result;
    }

    isolated remote function SearchPropertyContext(SearchPropertyRequest|ContextSearchPropertyRequest req) returns ContextSearchPropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        SearchPropertyRequest message;
        if req is ContextSearchPropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("rental.RentalService/SearchProperty", message, headers);
        [anydata, map<string|string[]>] [result, respHeaders] = payload;
        return {content: <SearchPropertyResponse>result, headers: respHeaders};
    }

    isolated remote function BookProperty(BookPropertyRequest|ContextBookPropertyRequest req) returns BookPropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        BookPropertyRequest message;
        if req is ContextBookPropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("rental.RentalService/BookProperty", message, headers);
        [anydata, map<string|string[]>] [result, _] = payload;
        return <BookPropertyResponse>result;
    }

    isolated remote function BookPropertyContext(BookPropertyRequest|ContextBookPropertyRequest req) returns ContextBookPropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        BookPropertyRequest message;
        if req is ContextBookPropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("rental.RentalService/BookProperty", message, headers);
        [anydata, map<string|string[]>] [result, respHeaders] = payload;
        return {content: <BookPropertyResponse>result, headers: respHeaders};
    }

    isolated remote function ConfirmBooking(ConfirmBookingRequest|ContextConfirmBookingRequest req) returns ConfirmBookingResponse|grpc:Error {
        map<string|string[]> headers = {};
        ConfirmBookingRequest message;
        if req is ContextConfirmBookingRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("rental.RentalService/ConfirmBooking", message, headers);
        [anydata, map<string|string[]>] [result, _] = payload;
        return <ConfirmBookingResponse>result;
    }

    isolated remote function ConfirmBookingContext(ConfirmBookingRequest|ContextConfirmBookingRequest req) returns ContextConfirmBookingResponse|grpc:Error {
        map<string|string[]> headers = {};
        ConfirmBookingRequest message;
        if req is ContextConfirmBookingRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC("rental.RentalService/ConfirmBooking", message, headers);
        [anydata, map<string|string[]>] [result, respHeaders] = payload;
        return {content: <ConfirmBookingResponse>result, headers: respHeaders};
    }

    isolated remote function CreateUsers() returns CreateUsersStreamingClient|grpc:Error {
        grpc:StreamingClient sClient = check self.grpcClient->executeClientStreaming("rental.RentalService/CreateUsers");
        return new CreateUsersStreamingClient(sClient);
    }

    isolated remote function ListAvailableProperties(ListAvailablePropertiesRequest|ContextListAvailablePropertiesRequest req) returns stream<Property, grpc:Error?>|grpc:Error {
        map<string|string[]> headers = {};
        ListAvailablePropertiesRequest message;
        if req is ContextListAvailablePropertiesRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeServerStreaming("rental.RentalService/ListAvailableProperties", message, headers);
        [stream<anydata, grpc:Error?>, map<string|string[]>] [result, _] = payload;
        PropertyStream outputStream = new PropertyStream(result);
        return new stream<Property, grpc:Error?>(outputStream);
    }

    isolated remote function ListAvailablePropertiesContext(ListAvailablePropertiesRequest|ContextListAvailablePropertiesRequest req) returns ContextPropertyStream|grpc:Error {
        map<string|string[]> headers = {};
        ListAvailablePropertiesRequest message;
        if req is ContextListAvailablePropertiesRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeServerStreaming("rental.RentalService/ListAvailableProperties", message, headers);
        [stream<anydata, grpc:Error?>, map<string|string[]>] [result, respHeaders] = payload;
        PropertyStream outputStream = new PropertyStream(result);
        return {content: new stream<Property, grpc:Error?>(outputStream), headers: respHeaders};
    }
}

public isolated client class CreateUsersStreamingClient {
    private final grpc:StreamingClient sClient;

    isolated function init(grpc:StreamingClient sClient) {
        self.sClient = sClient;
    }

    isolated remote function sendUser(User message) returns grpc:Error? {
        return self.sClient->send(message);
    }

    isolated remote function sendContextUser(ContextUser message) returns grpc:Error? {
        return self.sClient->send(message);
    }

    isolated remote function receiveCreateUsersResponse() returns CreateUsersResponse|grpc:Error? {
        var response = check self.sClient->receive();
        if response is () {
            return response;
        } else {
            [anydata, map<string|string[]>] [payload, _] = response;
            return <CreateUsersResponse>payload;
        }
    }

    isolated remote function receiveContextCreateUsersResponse() returns ContextCreateUsersResponse|grpc:Error? {
        var response = check self.sClient->receive();
        if response is () {
            return response;
        } else {
            [anydata, map<string|string[]>] [payload, headers] = response;
            return {content: <CreateUsersResponse>payload, headers: headers};
        }
    }

    isolated remote function sendError(grpc:Error response) returns grpc:Error? {
        return self.sClient->sendError(response);
    }

    isolated remote function complete() returns grpc:Error? {
        return self.sClient->complete();
    }
}

public class PropertyStream {
    private stream<anydata, grpc:Error?> anydataStream;

    public isolated function init(stream<anydata, grpc:Error?> anydataStream) {
        self.anydataStream = anydataStream;
    }

    public isolated function next() returns record {|Property value;|}|grpc:Error? {
        var streamValue = self.anydataStream.next();
        if streamValue is () {
            return streamValue;
        } else if streamValue is grpc:Error {
            return streamValue;
        } else {
            record {|Property value;|} nextRecord = {value: <Property>streamValue.value};
            return nextRecord;
        }
    }

    public isolated function close() returns grpc:Error? {
        return self.anydataStream.close();
    }
}

public type ContextUserStream record {|
    stream<User, error?> content;
    map<string|string[]> headers;
|};

public type ContextPropertyStream record {|
    stream<Property, error?> content;
    map<string|string[]> headers;
|};

public type ContextUpdatePropertyResponse record {|
    UpdatePropertyResponse content;
    map<string|string[]> headers;
|};

public type ContextBookPropertyRequest record {|
    BookPropertyRequest content;
    map<string|string[]> headers;
|};

public type ContextUser record {|
    User content;
    map<string|string[]> headers;
|};

public type ContextUpdatePropertyRequest record {|
    UpdatePropertyRequest content;
    map<string|string[]> headers;
|};

public type ContextSearchPropertyResponse record {|
    SearchPropertyResponse content;
    map<string|string[]> headers;
|};

public type ContextConfirmBookingRequest record {|
    ConfirmBookingRequest content;
    map<string|string[]> headers;
|};

public type ContextConfirmBookingResponse record {|
    ConfirmBookingResponse content;
    map<string|string[]> headers;
|};

public type ContextListAvailablePropertiesRequest record {|
    ListAvailablePropertiesRequest content;
    map<string|string[]> headers;
|};

public type ContextAddPropertyResponse record {|
    AddPropertyResponse content;
    map<string|string[]> headers;
|};

public type ContextRemovePropertyRequest record {|
    RemovePropertyRequest content;
    map<string|string[]> headers;
|};

public type ContextAddPropertyRequest record {|
    AddPropertyRequest content;
    map<string|string[]> headers;
|};

public type ContextRemovePropertyResponse record {|
    RemovePropertyResponse content;
    map<string|string[]> headers;
|};

public type ContextCreateUsersResponse record {|
    CreateUsersResponse content;
    map<string|string[]> headers;
|};

public type ContextSearchPropertyRequest record {|
    SearchPropertyRequest content;
    map<string|string[]> headers;
|};

public type ContextProperty record {|
    Property content;
    map<string|string[]> headers;
|};

public type ContextBookPropertyResponse record {|
    BookPropertyResponse content;
    map<string|string[]> headers;
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type UpdatePropertyResponse record {|
    boolean success = false;
    string message = "";
    Property property = {};
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type BookPropertyRequest record {|
    string guestId = "";
    string propertyId = "";
    string checkIn = "";
    string checkOut = "";
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type UserCreationError record {|
    string userId = "";
    string reason = "";
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type User record {|
    string userId = "";
    string name = "";
    string email = "";
    UserRole role = USER_ROLE_UNSPECIFIED;
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type UpdatePropertyRequest record {|
    string propertyId = "";
    string hostId = "";
    string location?;
    string name?;
    PropertyType propertyType?;
    PropertyStatus status?;
    float pricePerNight?;
|};

isolated function isValidUpdatepropertyrequest(UpdatePropertyRequest r) returns boolean {
    int _locationCount = 0;
    if r?.location !is () {
        _locationCount += 1;
    }
    int _nameCount = 0;
    if r?.name !is () {
        _nameCount += 1;
    }
    int _propertyTypeCount = 0;
    if r?.propertyType !is () {
        _propertyTypeCount += 1;
    }
    int _statusCount = 0;
    if r?.status !is () {
        _statusCount += 1;
    }
    int _pricePerNightCount = 0;
    if r?.pricePerNight !is () {
        _pricePerNightCount += 1;
    }
    if _locationCount > 1 || _nameCount > 1 || _propertyTypeCount > 1 || _statusCount > 1 || _pricePerNightCount > 1 {
        return false;
    }
    return true;
}

isolated function setUpdatePropertyRequest_Location(UpdatePropertyRequest r, string location) {
    r.location = location;
}

isolated function setUpdatePropertyRequest_Name(UpdatePropertyRequest r, string name) {
    r.name = name;
}

isolated function setUpdatePropertyRequest_PropertyType(UpdatePropertyRequest r, PropertyType propertyType) {
    r.propertyType = propertyType;
}

isolated function setUpdatePropertyRequest_Status(UpdatePropertyRequest r, PropertyStatus status) {
    r.status = status;
}

isolated function setUpdatePropertyRequest_PricePerNight(UpdatePropertyRequest r, float pricePerNight) {
    r.pricePerNight = pricePerNight;
}

@protobuf:Descriptor {value: RENTAL_DESC}
public type SearchPropertyResponse record {|
    boolean success = false;
    string message = "";
    Property property?;
|};

isolated function isValidSearchpropertyresponse(SearchPropertyResponse r) returns boolean {
    int _propertyCount = 0;
    if r?.property !is () {
        _propertyCount += 1;
    }
    if _propertyCount > 1 {
        return false;
    }
    return true;
}

isolated function setSearchPropertyResponse_Property(SearchPropertyResponse r, Property property) {
    r.property = property;
}

@protobuf:Descriptor {value: RENTAL_DESC}
public type Booking record {|
    string bookingId = "";
    string propertyId = "";
    string guestId = "";
    string checkIn = "";
    string checkOut = "";
    float totalCost = 0.0;
    int nights = 0;
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type ConfirmBookingRequest record {|
    string guestId = "";
    string cartItemId = "";
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type ConfirmBookingResponse record {|
    boolean success = false;
    string message = "";
    Booking booking?;
|};

isolated function isValidConfirmbookingresponse(ConfirmBookingResponse r) returns boolean {
    int _bookingCount = 0;
    if r?.booking !is () {
        _bookingCount += 1;
    }
    if _bookingCount > 1 {
        return false;
    }
    return true;
}

isolated function setConfirmBookingResponse_Booking(ConfirmBookingResponse r, Booking booking) {
    r.booking = booking;
}

@protobuf:Descriptor {value: RENTAL_DESC}
public type ListAvailablePropertiesRequest record {|
    float maxPrice?;
    string location?;
    float minPrice?;
|};

isolated function isValidListavailablepropertiesrequest(ListAvailablePropertiesRequest r) returns boolean {
    int _maxPriceCount = 0;
    if r?.maxPrice !is () {
        _maxPriceCount += 1;
    }
    int _locationCount = 0;
    if r?.location !is () {
        _locationCount += 1;
    }
    int _minPriceCount = 0;
    if r?.minPrice !is () {
        _minPriceCount += 1;
    }
    if _maxPriceCount > 1 || _locationCount > 1 || _minPriceCount > 1 {
        return false;
    }
    return true;
}

isolated function setListAvailablePropertiesRequest_MaxPrice(ListAvailablePropertiesRequest r, float maxPrice) {
    r.maxPrice = maxPrice;
}

isolated function setListAvailablePropertiesRequest_Location(ListAvailablePropertiesRequest r, string location) {
    r.location = location;
}

isolated function setListAvailablePropertiesRequest_MinPrice(ListAvailablePropertiesRequest r, float minPrice) {
    r.minPrice = minPrice;
}

@protobuf:Descriptor {value: RENTAL_DESC}
public type AddPropertyResponse record {|
    boolean success = false;
    string message = "";
    string propertyId = "";
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type RemovePropertyRequest record {|
    string propertyId = "";
    string hostId = "";
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type AddPropertyRequest record {|
    string hostId = "";
    string name = "";
    string location = "";
    string region = "";
    PropertyType propertyType = PROPERTY_TYPE_UNSPECIFIED;
    float pricePerNight = 0.0;
    PropertyStatus status = PROPERTY_STATUS_UNSPECIFIED;
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type RemovePropertyResponse record {|
    boolean success = false;
    string message = "";
    string region = "";
    Property[] properties = [];
    int count = 0;
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type CreateUsersResponse record {|
    boolean success = false;
    string message = "";
    int createdCount = 0;
    string[] createdUserIds = [];
    int failedCount = 0;
    UserCreationError[] errors = [];
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type SearchPropertyRequest record {|
    string propertyId = "";
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type Property record {|
    string propertyId = "";
    string hostId = "";
    string name = "";
    string location = "";
    string region = "";
    PropertyType propertyType = PROPERTY_TYPE_UNSPECIFIED;
    float pricePerNight = 0.0;
    PropertyStatus status = PROPERTY_STATUS_UNSPECIFIED;
|};

@protobuf:Descriptor {value: RENTAL_DESC}
public type BookPropertyResponse record {|
    boolean success = false;
    string message = "";
    string cartItemId = "";
    int nights = 0;
    float estimatedCost = 0.0;
|};

public enum PropertyStatus {
    PROPERTY_STATUS_UNSPECIFIED, AVAILABLE, UNAVAILABLE, MAINTENANCE
}

public enum UserRole {
    USER_ROLE_UNSPECIFIED, HOST, GUEST
}

public enum PropertyType {
    PROPERTY_TYPE_UNSPECIFIED, APARTMENT, HOUSE, COTTAGE, LODGE, GUEST_HOUSE, CAMPSITE
}
