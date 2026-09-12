<<<<<<< HEAD
// Server-only state. Not part of the wire contract - the client
// holds only a cartItemId, so the cart never crosses the network.

=======
>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876
public type CartItem record {|
    string cartItemId;
    string guestId;
    string propertyId;
<<<<<<< HEAD
    string checkIn;         // ISO YYYY-MM-DD
    string checkOut;
    int nights;
    decimal estimatedCost;
=======
    string checkIn;
    string checkOut;
    float estimatedCost;
    int nights;
>>>>>>> 2f44e7551db2b8dcc7b2b106af098b2f127b9876
|};