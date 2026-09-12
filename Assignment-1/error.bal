// 1. Define the structure for your custom error details

type GeneralError record {|
    string id;
    string reason;
|};

type InstitutionInUseDetails record {|
    string institutionName;
    int ownedCount;
|};

// 2. Define the custom error type constrained by your record
type AssetNotFound error<GeneralError>;
type WorkOrderNotFound error<GeneralError>;
type InstituteNotFound error<GeneralError>;
type ScheduleNotFound error<GeneralError>;
type ComponentNotFound error<GeneralError>;
type TaskNotFound error<GeneralError>;
type WorkOrderClosed error<GeneralError>;
type AssetDisposed error<GeneralError>;
type AssetBlocked error<GeneralError>;
type AssetOccupied error<GeneralError>;

type ScheduleExists error<GeneralError>;
type AssetExists error<GeneralError>;
type TaskExists error<GeneralError>;
type ComponentExists error<GeneralError>;
type InstituteExists error<GeneralError>;
type WorkOrderAndScheduleExists error<GeneralError>;

type InstitutionInUseError error<InstitutionInUseDetails>;

type InvalidAssetState error<GeneralError>;

