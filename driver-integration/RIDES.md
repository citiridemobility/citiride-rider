# Live ride matching (driver ↔ rider)

Collection: `rides/{rideId}`  
Live GPS (preferred): `driverLocations/{driverId}`  
Optional mirror on the ride: `rides/{rideId}.driverLocation`

## Status machine

```text
requested → accepted → arriving → waiting → in_progress → confirm_fare → completed
                 ↘ cancelled (from several early states)
```

Rider creates `requested`. Driver accepts and owns the rest.

## 1. Listen for open requests

```ts
firestore()
  .collection('rides')
  .where('status', '==', 'requested')
  .onSnapshot((snap) => {
    const open = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    // Show in UI (filter by distance client-side for now)
  });
```

Open request shape:

```ts
{
  riderId: string;
  driverId: null;
  status: 'requested';
  pickup: { lat: number; lng: number; address: string };
  destination: { lat: number; lng: number; address: string };
  fare: { estimated: number; final: number | null };
  rideType: 'regular' | 'vip';
  paymentMethod: 'cash' | 'wallet';
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
```

## 2. Accept a ride

Driver **must** be signed in. Use Auth UID as `driverId`.

```ts
const driverId = auth().currentUser!.uid;

await firestore().collection('rides').doc(rideId).update({
  status: 'accepted',
  driverId,
  updatedAt: firestore.FieldValue.serverTimestamp(),
});
```

Rules only allow this when:

- ride `status` is still `requested`
- `driverId` in the write equals `request.auth.uid`

First driver to succeed wins; others get a permission / precondition failure — handle and refresh the list.

## 3. Progress the trip

Keep `driverId` unchanged. Update `status` + `updatedAt`:

| When | status |
|------|--------|
| Heading to pickup | `arriving` |
| At pickup, waiting for rider | `waiting` |
| Trip started | `in_progress` |
| Trip ended, confirm price | `confirm_fare` |
| Done | `completed` |
| Cancel | `cancelled` |

```ts
await firestore().collection('rides').doc(rideId).update({
  status: 'arriving',
  updatedAt: firestore.FieldValue.serverTimestamp(),
});
```

The rider Flutter app watches the same doc and navigates screens from these statuses.

## 4. Publish live location

### Preferred: `driverLocations/{driverId}`

```ts
await firestore().collection('driverLocations').doc(driverId).set(
  {
    lat,
    lng,
    heading, // degrees, 0–360
    updatedAt: firestore.FieldValue.serverTimestamp(),
  },
  { merge: true },
);
```

Write on a timer / location stream (e.g. every 2–5s while on a trip).

### Optional: mirror on the ride

```ts
await firestore().collection('rides').doc(rideId).update({
  driverLocation: { lat, lng, heading, updatedAt: firestore.FieldValue.serverTimestamp() },
  updatedAt: firestore.FieldValue.serverTimestamp(),
});
```

Rider listens to both; either is enough for the map marker.

## 5. Final fare (optional later)

On `confirm_fare` / `completed`, you may set:

```ts
{
  fare: {
    estimated: existingEstimated,
    final: computedFinalAmount,
  }
}
```

Estimated fare is already set by the rider using live route math:

- Regular: ₦500 + ₦120/km + ₦10/min  
- VIP: ₦650 + ₦145/km + ₦12/min  
- Waiting: ₦10/min after 3 free minutes  

## Indexes

If the console prompts for a composite index on `(status)` alone it usually is not needed. For rider-side open requests we use `(riderId, status)` — already defined in the rider repo `firestore.indexes.json`.

## Security (what fails in practice)

| Mistake | Result |
|---------|--------|
| Not signed in | accept denied |
| `driverId` ≠ Auth UID | accept denied |
| Ride already accepted | accept denied |
| Writing another driver’s `driverLocations/{id}` | write denied |
