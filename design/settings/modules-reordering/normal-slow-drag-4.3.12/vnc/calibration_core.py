"""Move-only two-waypoint gate, adapted from reviewed direct_vz 20378286."""
import time


def calibrate_moves(client, point, display_bounds, map_point, read_cursor, check_peer, report):
    def distance(a, b):
        return max(abs(float(a[key]) - float(b[key])) for key in ('x', 'y'))
    x, y, width, height = map(float, display_bounds)
    before = read_cursor()
    candidates = [{'x': x + width * fx, 'y': y + height * fy}
                  for fx in (0.25, 0.5, 0.75) for fy in (0.25, 0.5, 0.75)]
    waypoint = next((p for p in candidates if distance(p, point) >= 8 and distance(p, before['pointerCG']) >= 8), None)
    if waypoint is None:
        raise ValueError('No distinct interior calibration waypoint')
    proof = {'requestedCGPoint': point, 'mappedRFBPoint': map_point(point), 'before': before,
             'waypointCGPoint': waypoint, 'mappedWaypoint': map_point(waypoint),
             'passed': False, 'mouseDownMessages': 0}
    report['calibration'] = proof
    for stage, target in [('waypoint', waypoint), ('source', point)]:
        check_peer()
        client.pointer(0, map_point(target))
        time.sleep(0.2)
        observed = read_cursor()  # Caller keeps this same RFB socket open.
        error = distance(observed['pointerCG'], target)
        proof[stage + 'Readback'] = observed
        proof[stage + 'MaxLogicalPointError'] = error
        if error > 1:
            raise ValueError('Move-only native cursor calibration failed; no down permitted')
    proof.update(afterWhileSocketOpen=proof['sourceReadback'], maxLogicalPointError=proof['sourceMaxLogicalPointError'],
                 observedMovement=True, passed=True)
