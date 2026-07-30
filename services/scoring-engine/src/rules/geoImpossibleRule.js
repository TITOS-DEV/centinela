const RULE_ID = "geo_impossible";
const POINTS = Number(process.env.RULE_GEO_POINTS || 40);
const MAX_PLAUSIBLE_SPEED_KMH = Number(process.env.RULE_GEO_MAX_SPEED_KMH || 1000);

const EARTH_RADIUS_KM = 6371;

function toRadians(deg) {
  return (deg * Math.PI) / 180;
}

/** Distancia entre dos coordenadas por la formula de Haversine, en km. */
function haversineDistanceKm(loc1, loc2) {
  const dLat = toRadians(loc2.lat - loc1.lat);
  const dLon = toRadians(loc2.lon - loc1.lon);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(loc1.lat)) * Math.cos(toRadians(loc2.lat)) * Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_RADIUS_KM * c;
}

/**
 * Compara la transaccion actual contra la inmediatamente anterior de la
 * misma cuenta (history[0], ya que viene ordenado DESC). Si la velocidad
 * implicita (distancia / tiempo) supera lo fisicamente plausible, activa.
 */
function evaluateGeoImpossible(currentTx, history) {
  const previousTx = history[0];

  if (!previousTx || !previousTx.location || !currentTx.location) {
    return {
      triggered: false,
      ruleId: RULE_ID,
      points: 0,
      observed: { reason: "sin transaccion previa o sin ubicacion para comparar" },
    };
  }

  const distanceKm = haversineDistanceKm(previousTx.location, currentTx.location);
  const msElapsed = new Date(currentTx.receivedAt).getTime() - new Date(previousTx.receivedAt).getTime();
  const hoursElapsed = msElapsed / 3_600_000;

  if (hoursElapsed <= 0) {
    return {
      triggered: false,
      ruleId: RULE_ID,
      points: 0,
      observed: { reason: "sin tiempo transcurrido medible desde la transaccion previa" },
    };
  }

  const impliedSpeedKmh = distanceKm / hoursElapsed;
  const triggered = impliedSpeedKmh > MAX_PLAUSIBLE_SPEED_KMH;

  return {
    triggered,
    ruleId: RULE_ID,
    points: triggered ? POINTS : 0,
    observed: {
      distanceKm: Number(distanceKm.toFixed(1)),
      hoursElapsed: Number(hoursElapsed.toFixed(2)),
      minutesElapsed: Number((msElapsed / 60_000).toFixed(1)),
      impliedSpeedKmh: Number(impliedSpeedKmh.toFixed(1)),
      maxPlausibleSpeedKmh: MAX_PLAUSIBLE_SPEED_KMH,
      previousTransactionId: previousTx.id,
      previousCity: previousTx.location.city || null,
      currentCity: currentTx.location.city || null,
    },
  };
}

module.exports = { evaluateGeoImpossible };
