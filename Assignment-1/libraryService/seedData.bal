// Sample records loaded when the service module starts.
function init() returns error? {
    Institution[] seedInstitutions = [
        {
            institutionId: "NUST",
            name: "National University of Science and Technology"
        },
        {
            institutionId: "UZ",
            name: "University of Zimbabwe"
        },
        {
            institutionId: "UCT",
            name: "University of Cape Town"
        }
    ];

    foreach Institution institution in seedInstitutions {
        _ = check addInstitution(institution);
    }

    Asset[] seedAssets = [
        {
            assetTag: "LAPTOP-001",
            name: "Dell Latitude 7440",
            description: "Development laptop available for student projects",
            institutionId: "NUST",
            site: "Harare",
            dateAcquired: "2025-02-15",
            status: AVAILABLE
        },
        {
            assetTag: "PROJECTOR-001",
            name: "Epson PowerLite Projector",
            description: "Portable projector for lecture rooms",
            institutionId: "NUST",
            site: "Harare",
            dateAcquired: "2024-08-20",
            status: AVAILABLE
        },
        {
            assetTag: "SERVER-001",
            name: "Dell PowerEdge R740",
            description: "Shared research compute server",
            institutionId: "UZ",
            site: "Mount Pleasant",
            dateAcquired: "2023-11-03",
            status: UNDER_MAINTENANCE
        },
        {
            assetTag: "CAMERA-001",
            name: "Sony Alpha A7 IV",
            description: "Media production camera",
            institutionId: "UCT",
            site: "Rondebosch",
            dateAcquired: "2025-04-11",
            status: AVAILABLE
        }
    ];

    foreach Asset asset in seedAssets {
        _ = check addAsset(asset);
    }
}
