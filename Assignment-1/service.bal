import ballerina/http;

service / on new http:Listener(9091) {

    // --- ASSETS ---

    resource function get assets() returns Asset[] {
        return getAllAssets();
    }

    resource function get assets/[string assetTag]() returns Asset|http:NotFound|error {
        Asset|error asset = getAsset(assetTag);
        if asset is error {
            return <http:NotFound>{body: {message: asset.message()}};
        }
        return asset;
    }

    resource function post assets(@http:Payload Asset newAsset) returns Asset|http:BadRequest|error {
        Asset|error result = addAsset(newAsset);
        if result is error {
            return <http:BadRequest>{body: {message: result.message()}};
        }
        return result;
    }

    resource function put assets/[string assetTag](@http:Payload AssetUpdate updates) returns Asset|http:NotFound|error {
        Asset|error result = updateAsset(assetTag, updates);
        if result is error {
            return <http:NotFound>{body: {message: result.message()}};
        }
        return result;
    }

    resource function delete assets/[string assetTag]() returns http:Ok|http:NotFound|error {
        error? result = deleteAsset(assetTag);
        if result is error {
            return <http:NotFound>{body: {message: result.message()}};
        }
        return http:OK;
    }

    // --- INSTITUTIONS ---

    resource function get institutions() returns Institution[] {
        return getAllInstitutions();
    }

    resource function get institutions/[string institutionId]() returns Institution|http:NotFound|error {
        Institution|error inst = getInstitution(institutionId);
        if inst is error {
            return <http:NotFound>{body: {message: inst.message()}};
        }
        return inst;
    }

    resource function post institutions(@http:Payload Institution newInst) returns Institution|http:BadRequest|error {
        Institution|error result = addInstitution(newInst);
        if result is error {
            return <http:BadRequest>{body: {message: result.message()}};
        }
        return result;
    }
}