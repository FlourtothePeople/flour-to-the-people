// Shipping: the cheapest USPS option at Click-N-Ship (commercial) prices,
// from the mill in Floyd, VA (ZIP 24091) to the customer's ZIP code.
//
// Prices: USPS Notice 123, effective July 12, 2026 (pe.usps.com).
// Zones:  USPS domestic zone chart for origin ZIP3 240, effective October 1, 2026
//         (postcalc.usps.com/DomesticZoneChart). Update both when USPS changes prices
//         (usually January and July).
//
// For each order the calculator compares:
//   - USPS Ground Advantage by weight (flour + packaging, rounded up to the pound)
//   - Priority Mail Padded Flat Rate Envelope / Medium / Large Flat Rate Box,
//     when the order fits (FLAT_RATE capacities below, in 1.5 lb bag equivalents)
// and charges the cheapest. The chosen method is returned so the mill knows
// which label to buy.

// Packaging weight added to the flour weight, in ounces.
export const PACKAGING_OZ = { mailer: 4, box: 8 };
// Orders up to this many 1.5 lb bag-equivalents (24 oz) ship in a poly mailer.
export const MAILER_MAX_BAGS = 2;

// Priority Mail Flat Rate, commercial prices in cents. maxBags = how many 1.5 lb
// bag-equivalents fit (a 3 lb all-purpose bag counts as 2). Adjust to what
// actually fits in your packaging.
export const FLAT_RATE = [
  { name: 'Priority Mail Padded Flat Rate Envelope', cents: 1199, maxBags: 2 },
  { name: 'Priority Mail Medium Flat Rate Box',      cents: 2117, maxBags: 4 },
  { name: 'Priority Mail Large Flat Rate Box',       cents: 3100, maxBags: 6 },
];

// USPS Ground Advantage commercial prices in cents.
// Row = weight in pounds (row 0 = 1 lb ... row 69 = 70 lb); column = zone 1..9.
const GROUND_ADVANTAGE = [
  [  761,   768,   800,   815,   874,   963,   998,  1067,  1067],
  [  799,   808,   826,   851,   995,  1158,  1200,  1287,  1287],
  [  864,   866,   914,   967,  1157,  1359,  1436,  1575,  1575],
  [  928,   934,   970,  1065,  1284,  1516,  1619,  1801,  1801],
  [  970,   976,  1014,  1102,  1348,  1589,  1712,  1919,  1919],
  [  987,   994,  1036,  1155,  1428,  1689,  1831,  2068,  2068],
  [  996,  1002,  1062,  1190,  1490,  1765,  1923,  2183,  2183],
  [ 1010,  1027,  1149,  1243,  1549,  1834,  2008,  2290,  2290],
  [ 1101,  1125,  1239,  1365,  1611,  1913,  2101,  2409,  2409],
  [ 1191,  1226,  1318,  1444,  1676,  1994,  2197,  2534,  2534],
  [ 1275,  1294,  1400,  1518,  1812,  2128,  2368,  2737,  2737],
  [ 1349,  1385,  1463,  1589,  1886,  2220,  2478,  2873,  2873],
  [ 1415,  1448,  1525,  1653,  1962,  2316,  2587,  3011,  3011],
  [ 1473,  1507,  1581,  1713,  2038,  2414,  2699,  3153,  3153],
  [ 1523,  1553,  1631,  1767,  2115,  2513,  2811,  3291,  3291],
  [ 1564,  1591,  1673,  1794,  2189,  2609,  2922,  3429,  3429],
  [ 1597,  1629,  1715,  1841,  2251,  2685,  3011,  3542,  3542],
  [ 1621,  1646,  1761,  1894,  2316,  2770,  3109,  3664,  3664],
  [ 1638,  1682,  1781,  1936,  2379,  2852,  3207,  3784,  3784],
  [ 1646,  1706,  1803,  1966,  2493,  3032,  3467,  4039,  4039],
  [ 1848,  1954,  2066,  2179,  2613,  3169,  3796,  4301,  4301],
  [ 1986,  2122,  2259,  2407,  2945,  3673,  4433,  4974,  4974],
  [ 2151,  2316,  2492,  2733,  3405,  4329,  5214,  5841,  5841],
  [ 2344,  2527,  2764,  3162,  3994,  5128,  6140,  6897,  6897],
  [ 2532,  2754,  3072,  3660,  4694,  5824,  6886,  7819,  7819],
  [ 2627,  2868,  3226,  3907,  5046,  6173,  7261,  8280,  8280],
  [ 2721,  2984,  3381,  4158,  5396,  6524,  7635,  8746,  8746],
  [ 2797,  3070,  3485,  4285,  5575,  6749,  7902,  9053,  9053],
  [ 2872,  3155,  3587,  4411,  5753,  6969,  8165,  9358,  9358],
  [ 2946,  3238,  3686,  4534,  5928,  7188,  8424,  9660,  9660],
  [ 3018,  3322,  3784,  4655,  6100,  7402,  8680,  9957,  9957],
  [ 3090,  3404,  3880,  4773,  6268,  7613,  8933, 10251, 10251],
  [ 3162,  3484,  3975,  4888,  6439,  7824,  9183, 10542, 10542],
  [ 3232,  3565,  4068,  5004,  6604,  8030,  9429, 10829, 10829],
  [ 3304,  3643,  4161,  5118,  6769,  8237,  9677, 11116, 11116],
  [ 3371,  3721,  4251,  5225,  6926,  8433,  9914, 11394, 11394],
  [ 3441,  3799,  4341,  5335,  7086,  8632, 10154, 11674, 11674],
  [ 3508,  3875,  4428,  5444,  7244,  8831, 10390, 11951, 11951],
  [ 3577,  3950,  4513,  5549,  7400,  9027, 10622, 12225, 12225],
  [ 3644,  4024,  4598,  5654,  7551,  9217, 10852, 12496, 12496],
  [ 3709,  4098,  4681,  5759,  7704,  9408, 11080, 12762, 12762],
  [ 3776,  4168,  4762,  5859,  7852,  9594, 11305, 13028, 13028],
  [ 3840,  4240,  4844,  5957,  7998,  9779, 11527, 13288, 13288],
  [ 3905,  4309,  4920,  6054,  8141,  9960, 11745, 13545, 13545],
  [ 3968,  4378,  4999,  6150,  8285, 10139, 11961, 13801, 13801],
  [ 4033,  4445,  5075,  6242,  8423, 10317, 12175, 14052, 14052],
  [ 4094,  4512,  5149,  6333,  8560, 10490, 12382, 14300, 14300],
  [ 4156,  4578,  5222,  6422,  8697, 10661, 12590, 14545, 14545],
  [ 4217,  4642,  5292,  6510,  8830, 10829, 12794, 14788, 14788],
  [ 4277,  4707,  5363,  6596,  8960, 10994, 12995, 15027, 15027],
  [ 4335,  4771,  5429,  6679,  9088, 11157, 13192, 15263, 15263],
  [ 4395,  4831,  5495,  6761,  9215, 11318, 13386, 15495, 15495],
  [ 4453,  4892,  5561,  6840,  9338, 11475, 13579, 15725, 15725],
  [ 4510,  4951,  5625,  6918,  9461, 11631, 13767, 15949, 15949],
  [ 4567,  5010,  5685,  6995,  9580, 11784, 13953, 16174, 16174],
  [ 4622,  5067,  5747,  7070,  9698, 11932, 14135, 16393, 16393],
  [ 4679,  5124,  5805,  7142,  9811, 12081, 14315, 16610, 16610],
  [ 4733,  5178,  5862,  7211,  9924, 12223, 14491, 16823, 16823],
  [ 4788,  5234,  5918,  7281, 10035, 12367, 14664, 17033, 17033],
  [ 4839,  5287,  5971,  7346, 10142, 12504, 14835, 17239, 17239],
  [ 4892,  5340,  6024,  7412, 10248, 12641, 15002, 17444, 17444],
  [ 4945,  5389,  6076,  7474, 10351, 12776, 15166, 17644, 17644],
  [ 4995,  5441,  6125,  7534, 10453, 12907, 15328, 17842, 17842],
  [ 5046,  5490,  6173,  7593, 10553, 13035, 15487, 18036, 18036],
  [ 5094,  5538,  6219,  7651, 10649, 13160, 15642, 18225, 18225],
  [ 5144,  5585,  6263,  7706, 10743, 13283, 15793, 18413, 18413],
  [ 5193,  5630,  6306,  7760, 10835, 13404, 15944, 18598, 18598],
  [ 5241,  5676,  6349,  7811, 10925, 13522, 16090, 18779, 18779],
  [ 5288,  5720,  6387,  7861, 11013, 13634, 16233, 18957, 18957],
  [ 5333,  5763,  6426,  7908, 11097, 13746, 16373, 19131, 19131]
];

const MAX_PACKAGE_LB = 70;

// Zone by 3-digit ZIP prefix: character i of this string is the zone for ZIP3 i
// ("0" = prefix not in use).
const ZONE_BY_ZIP3 = '0000047777444444455555555554445555455555555555555554445555554444444444444444444444444444444444444444444444444444444444444444444445444444444444444444443333333343333444344434333444444444444444444444444333333333333330333334333333332223333333321121222222232232232233223323201222222233222333233333333332343444433433444444444444444444455555555555555040550544404444444444445444444344233344444345444554555444344333333333233223204444433400333344433344333333433334333343444444444444444444444444444444444444445555555555555555555000555555555054404505555555555555550555555555555666005566666600666666667077777777884444444444545454444440454444444405554444550055555555555555505550555555665556666655055556666666000000550555555055555055555554455555550656656655055555555555555555665666666650556555666666666666666666667766667666666777777000676777777777877888807777777700777807770770088700007707777677766767000888088808808888888880888888888888888888808888888888888888888888888888888888888889888888888888888880888888888888';
// 5-digit exceptions to the 3-digit chart: [first, last, zone].
const ZONE_EXCEPTIONS = [
  ['09000', '09999', 4], ['96200', '96699', 4], ['96900', '96938', 8],
  ['96945', '96959', 8], ['96961', '96969', 8], ['96971', '96999', 8],
];

export function zoneForZip(postal_code) {
  const zip = String(postal_code || '').trim().slice(0, 5);
  if (!/^\d{5}$/.test(zip)) return null;
  for (const [a, b, z] of ZONE_EXCEPTIONS) if (zip >= a && zip <= b) return z;
  const z = Number(ZONE_BY_ZIP3[Number(zip.slice(0, 3))]);
  return z > 0 ? z : null;
}

function groundAdvantageCents(weight_oz, zone) {
  const lb = Math.max(1, Math.ceil(weight_oz / 16));
  return GROUND_ADVANTAGE[lb - 1][zone - 1];
}

// Cheapest way to ship ONE package holding `bags` bag-equivalents (24 oz each).
function quotePackage(bags, zone) {
  const oz = bags * 24;
  const pack = bags <= MAILER_MAX_BAGS ? PACKAGING_OZ.mailer : PACKAGING_OZ.box;
  const lb = Math.ceil((oz + pack) / 16);
  if (lb > MAX_PACKAGE_LB) return null;
  let best = { method: 'USPS Ground Advantage, ' + lb + ' lb', cents: groundAdvantageCents(oz + pack, zone) };
  for (const f of FLAT_RATE) {
    if (bags <= f.maxBags && f.cents < best.cents) best = { method: f.name, cents: f.cents };
  }
  return best;
}

// Returns { cents, zone, method } or throws Error with a user-safe message.
// Tries shipping the order as 1, 2, 3 ... packages (bags split as evenly as
// possible) and keeps the cheapest total.
export function calculateShipping(total_weight_oz, postal_code) {
  const zone = zoneForZip(postal_code);
  if (!zone) throw new Error('Please enter a valid US ZIP code for shipping');
  const bags = Math.max(1, Math.ceil(total_weight_oz / 24));
  let best = null;
  for (let n = 1; n <= bags; n++) {
    let cents = 0;
    const methods = [];
    let ok = true;
    for (let i = 0; i < n; i++) {
      const q = quotePackage(Math.floor(bags / n) + (i < bags % n ? 1 : 0), zone);
      if (!q) { ok = false; break; }
      cents += q.cents;
      methods.push(q.method);
    }
    if (ok && (!best || cents < best.cents)) best = { cents, n, methods };
  }
  const method = best.n === 1 ? best.methods[0] : best.n + ' packages: ' + best.methods.join(' + ');
  return { cents: best.cents, zone, method };
}
