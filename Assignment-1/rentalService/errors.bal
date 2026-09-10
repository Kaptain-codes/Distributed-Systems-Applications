type GeneralError record {|
    string id;
    string reason;
|};

type PropertyNotFound   error<GeneralError>;
type PropertyExists     error<GeneralError>;
type NotPropertyOwner   error<GeneralError>;
type UserNotFound       error<GeneralError>;
type UserExists         error<GeneralError>;
type CartItemNotFound   error<GeneralError>;
type DatesUnavailable   error<GeneralError>;
type InvalidDateRange   error<GeneralError>;
type ValidationError    error<GeneralError>;
