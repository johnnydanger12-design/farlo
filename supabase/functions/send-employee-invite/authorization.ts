// Pure ownership check, extracted so it's unit-testable — security.md §4
// Consolidated Risk Register, Medium: "send-employee-invite ... performs
// zero authorization." This function previously trusted whatever
// email/truckName/ownerName the client sent with no verification at all
// that the caller actually owned the truck they claimed to be inviting for.

export interface TruckRow {
  name: string;
  owner_id: string;
}

export function callerOwnsTruck(truck: TruckRow | null, callerId: string): boolean {
  return truck !== null && truck.owner_id === callerId;
}
