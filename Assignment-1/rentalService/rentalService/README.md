# Rental Accommodation Service (Q2)

gRPC service for the DSA612S Assignment 1 rental system.
Ballerina 2201.13.4. Listens on **port 9091** (9090 is libraryService).

## Running

    bal run

## Regenerating stubs

Server:
    bal grpc --mode service --input rental.proto --output .
Client:
    bal grpc --mode client --input rental.proto --output ../rentalClient

## Design notes

- Dates are ISO YYYY-MM-DD strings. They sort lexicographically the
  same way they sort chronologically, so overlap detection needs no
  date library.
- Overlap uses strict `<` on both sides, so a checkout on the 15th
  does not block a check-in on the 15th (standard hotel turnover).
- Storage is `isolated map<T>` with all access inside `lock` blocks.
  Returns are cloned so callers cannot mutate stored state.
- Expected failures return `success: false` with a message. gRPC
  errors are reserved for genuinely exceptional conditions.
- `cartItemId` was added to the contract because ConfirmBooking has
  no other way to identify which pending request to finalise.

## Known limitations

- ConfirmBooking reads three tables (cart, property, booking).
  Ballerina does not permit a single `lock` to access more than one
  isolated global, so a narrow race window exists between the overlap
  check and the booking write. Documented rather than worked around,
  as libraryService does for the same constraint.
- `CreateUsers` is not an isolated method, so calls to it are
  serialised rather than concurrent.

## Testing

The full suite stalls when all 25 tests run in one process — cause not
yet identified. Every test passes when run in two batches. See
TESTING.md for the exact commands.