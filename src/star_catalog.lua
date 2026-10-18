-- The bright stars, as they actually are.
--
-- Every entry is a real star at its real J2000 position, with its real visual
-- magnitude and its real colour index. That is the whole point: a procedural
-- star field of the right density still reads as noise, because what a person
-- recognises in a night sky is not how many stars there are but the handful of
-- shapes -- Orion's belt, the Plough, the W of Cassiopeia, the Southern Cross --
-- that only appear if the stars are in the places they belong.
--
-- Coverage is everything brighter than about magnitude 3, plus the fainter
-- members that constellation figures and the well-known clusters need. Below
-- that the eye stops resolving individuals and `star_field` fills in a
-- procedural background whose density follows galactic latitude, which is what
-- the faint sky is: the Milky Way's own disc seen edge on.
--
-- Columns are right ascension in hours, declination in degrees, visual
-- magnitude, and B-V colour index. B-V runs from about -0.3 for the hottest
-- blue stars through 0.0 at Vega and 0.65 at the sun to 1.9 for the coolest red
-- giants, and `star_field` turns it into a colour temperature.

local catalog = {}

catalog.stars = {
  -- name                     RA(h)     Dec(deg)   V      B-V
  {"Sirius",                  6.75248,  -16.7161, -1.46,  0.00},
  {"Canopus",                 6.39920,  -52.6957, -0.72,  0.15},
  {"Rigil Kentaurus",        14.66014,  -60.8340, -0.27,  0.71},
  {"Arcturus",               14.26103,   19.1824, -0.05,  1.23},
  {"Vega",                   18.61565,   38.7837,  0.03,  0.00},
  {"Capella",                 5.27814,   45.9980,  0.08,  0.80},
  {"Rigel",                   5.24230,   -8.2016,  0.18, -0.03},
  {"Procyon",                 7.65503,    5.2250,  0.38,  0.42},
  {"Achernar",                1.62857,  -57.2367,  0.46, -0.16},
  {"Betelgeuse",              5.91953,    7.4070,  0.50,  1.85},
  {"Hadar",                  14.06373,  -60.3730,  0.61, -0.23},
  {"Altair",                 19.84639,    8.8683,  0.77,  0.22},
  {"Acrux",                  12.44330,  -63.0991,  0.77, -0.24},
  {"Aldebaran",               4.59868,   16.5093,  0.85,  1.54},
  {"Antares",                16.49013,  -26.4320,  0.96,  1.83},
  {"Spica",                  13.41989,  -11.1613,  0.98, -0.24},
  {"Pollux",                  7.75536,   28.0262,  1.14,  1.00},
  {"Fomalhaut",              22.96084,  -29.6222,  1.16,  0.09},
  {"Deneb",                  20.69053,   45.2803,  1.25,  0.09},
  {"Mimosa",                 12.79537,  -59.6888,  1.25, -0.24},
  {"Regulus",                10.13952,   11.9672,  1.35, -0.11},
  {"Adhara",                  6.97709,  -28.9721,  1.50, -0.21},
  {"Castor",                  7.57667,   31.8883,  1.58,  0.03},
  {"Shaula",                 17.56014,  -37.1038,  1.62, -0.22},
  {"Gacrux",                 12.51944,  -57.1132,  1.63,  1.60},
  {"Bellatrix",               5.41885,    6.3497,  1.64, -0.22},
  {"Elnath",                  5.43819,   28.6075,  1.65, -0.13},
  {"Miaplacidus",             9.21999,  -69.7172,  1.67,  0.07},
  {"Alnilam",                 5.60356,   -1.2019,  1.69, -0.18},
  {"Alnair",                 22.13721,  -46.9610,  1.74, -0.07},
  {"Alnitak",                 5.67931,   -1.9426,  1.74, -0.20},
  {"Regor",                   8.15888,  -47.3366,  1.78, -0.15},
  {"Alioth",                 12.90049,   55.9598,  1.77, -0.02},
  {"Mirfak",                  3.40538,   49.8612,  1.79,  0.48},
  {"Dubhe",                  11.06213,   61.7511,  1.79,  1.07},
  {"Wezen",                   7.13986,  -26.3932,  1.83,  0.67},
  {"Kaus Australis",         18.40287,  -34.3846,  1.85, -0.03},
  {"Alkaid",                 13.79237,   49.3133,  1.86, -0.19},
  {"Avior",                   8.37523,  -59.5095,  1.86,  1.20},
  {"Sargas",                 17.62200,  -42.9978,  1.87,  0.40},
  {"Menkalinan",              5.99216,   44.9474,  1.90,  0.08},
  {"Atria",                  16.81108,  -69.0277,  1.91,  1.44},
  {"Alhena",                  6.62853,   16.3993,  1.93,  0.00},
  {"Koo She",                 8.74501,  -54.7085,  1.93,  0.04},
  {"Peacock",                20.42746,  -56.7351,  1.94, -0.12},
  {"Polaris",                 2.53030,   89.2641,  1.98,  0.60},
  {"Mirzam",                  6.37833,  -17.9559,  1.98, -0.24},
  {"Alphard",                 9.45979,   -8.6586,  1.98,  1.44},
  {"Hamal",                   2.11952,   23.4624,  2.00,  1.15},
  {"Algieba",                10.33288,   19.8415,  2.01,  1.13},
  {"Deneb Kaitos",            0.72649,  -17.9866,  2.04,  1.02},
  {"Nunki",                  18.92109,  -26.2967,  2.05, -0.22},
  {"Alpheratz",               0.13979,   29.0904,  2.06, -0.11},
  {"Mirach",                  1.16217,   35.6206,  2.06,  1.58},
  {"Saiph",                   5.79594,   -9.6696,  2.06, -0.17},
  {"Menkent",                14.11137,  -36.3700,  2.06,  1.01},
  {"Kochab",                 14.84509,   74.1555,  2.07,  1.47},
  {"Rasalhague",             17.58224,   12.5600,  2.08,  0.15},
  {"Almach",                  2.06498,   42.3297,  2.10,  1.37},
  {"Tiaki",                  22.71110,  -46.8846,  2.11,  1.60},
  {"Algol",                   3.13614,   40.9556,  2.12, -0.05},
  {"Denebola",               11.81766,   14.5721,  2.14,  0.09},
  {"Cih",                     0.94515,   60.7167,  2.15, -0.15},
  {"Muhlifain",              12.69196,  -48.9599,  2.17, -0.01},
  {"Naos",                    8.05963,  -40.0031,  2.21, -0.27},
  {"Aspidiske",               9.28499,  -59.2753,  2.21,  0.18},
  {"Alphecca",               15.57813,   26.7147,  2.22, -0.02},
  {"Suhail",                  9.13327,  -43.4326,  2.23,  1.67},
  {"Sadr",                   20.37047,   40.2567,  2.23,  0.68},
  {"Mizar",                  13.39873,   54.9254,  2.23,  0.06},
  {"Eltanin",                17.94344,   51.4889,  2.23,  1.52},
  {"Mintaka",                 5.53344,   -0.2991,  2.23, -0.18},
  {"Schedar",                 0.67512,   56.5373,  2.24,  1.17},
  {"Caph",                    0.15297,   59.1498,  2.27,  0.34},
  {"Dschubba",               16.00555,  -22.6217,  2.29, -0.12},
  {"Larawag",                16.83606,  -34.2932,  2.29,  1.15},
  {"Epsilon Centauri",       13.66479,  -53.4664,  2.30, -0.22},
  {"Alpha Lupi",             14.69882,  -47.3882,  2.30, -0.20},
  {"Eta Centauri",           14.59178,  -42.1578,  2.31, -0.19},
  {"Izar",                   14.74978,   27.0742,  2.35,  0.97},
  {"Merak",                  11.03069,   56.3824,  2.37,  0.03},
  {"Girtab",                 17.70814,  -39.0299,  2.39, -0.22},
  {"Enif",                   21.73643,    9.8750,  2.39,  1.53},
  {"Ankaa",                   0.43800,  -42.3061,  2.40,  1.09},
  {"Scheat",                 23.06290,   28.0828,  2.42,  1.67},
  {"Sabik",                  17.17296,  -15.7250,  2.43,  0.06},
  {"Phecda",                 11.89718,   53.6948,  2.44,  0.04},
  {"Aludra",                  7.40158,  -29.3031,  2.45, -0.08},
  {"Alderamin",              21.30966,   62.5856,  2.45,  0.22},
  {"Kappa Velorum",           9.36856,  -55.0107,  2.47, -0.14},
  {"Gienah Cygni",           20.77019,   33.9703,  2.48,  1.03},
  {"Markab",                 23.07934,   15.2053,  2.49, -0.04},
  {"Menkar",                  3.03799,    4.0897,  2.53,  1.63},
  {"Zeta Centauri",          13.92578,  -47.2884,  2.55, -0.22},
  {"Zosma",                  11.23514,   20.5237,  2.56,  0.13},
  {"Delta Centauri",         12.13976,  -50.7226,  2.58, -0.12},
  {"Arneb",                   5.54550,  -17.8223,  2.58,  0.21},
  {"Gienah Corvi",           12.26343,  -17.5419,  2.59, -0.11},
  {"Zubeneschamali",         15.28297,   -9.3829,  2.61, -0.07},
  {"Ascella",                19.04347,  -29.8801,  2.60,  0.06},
  {"Theta Aurigae",           5.99527,   37.2126,  2.62, -0.08},
  {"Unukalhai",              15.73780,    6.4256,  2.63,  1.17},
  {"Sheratan",                1.91067,   20.8080,  2.64,  0.13},
  {"Phact",                   5.66081,  -34.0742,  2.65, -0.12},
  {"Kraz",                   12.57351,  -23.3966,  2.65,  0.89},
  {"Alpha Muscae",           12.61986,  -69.1355,  2.69, -0.19},
  {"Beta Lupi",              14.97551,  -43.1339,  2.68, -0.22},
  {"Mu Velorum",             10.77947,  -49.4202,  2.69,  0.90},
  {"Iota Aurigae",            4.94989,   33.1661,  2.69,  1.53},
  {"Kaus Media",             18.34990,  -29.8281,  2.70,  1.38},
  {"Pi Puppis",               7.28571,  -37.0975,  2.71,  1.62},
  {"Tarazed",                19.77099,   10.6133,  2.72,  1.52},
  {"Eta Draconis",           16.39988,   61.5141,  2.73,  0.91},
  {"Porrima",                12.69437,   -1.4494,  2.74,  0.36},
  {"Yed Prior",              16.23913,   -3.6944,  2.74,  1.58},
  {"Zubenelgenubi",          14.84797,  -16.0418,  2.75,  0.15},
  {"Iota Centauri",          13.34328,  -36.7123,  2.75,  0.06},
  {"Cebalrai",               17.72454,    4.5673,  2.76,  1.16},
  {"Theta Carinae",          10.71595,  -64.3945,  2.76, -0.22},
  {"Kornephoros",            16.50365,   21.4896,  2.77,  0.94},
  {"Gamma Lupi",             15.58521,  -41.1665,  2.78, -0.20},
  {"Delta Crucis",           12.25243,  -58.7489,  2.79, -0.19},
  {"Rastaban",               17.50723,   52.3014,  2.79,  0.95},
  {"Beta Hydri",              0.42917,  -77.2543,  2.80,  0.62},
  {"Zeta Herculis",          16.68829,   31.6033,  2.81,  0.65},
  {"Kaus Borealis",          18.46618,  -25.4217,  2.81,  1.02},
  {"Rho Puppis",              8.12581,  -24.3044,  2.81,  0.43},
  {"Vindemiatrix",           13.03625,   10.9591,  2.83,  0.94},
  {"Nihal",                   5.47075,  -20.7594,  2.84,  0.82},
  {"Beta Trianguli Australis", 15.91882, -63.4306, 2.85,  0.29},
  {"Deneb Algedi",           21.78397,  -16.1273,  2.85,  0.30},
  {"Zeta Persei",             3.90223,   31.8836,  2.85,  0.31},
  {"Alcyone",                 3.79141,   24.1052,  2.87,  -0.09},
  {"Tejat",                   6.38286,   22.5137,  2.87,  1.64},
  {"Delta Cygni",            19.74956,   45.1308,  2.87, -0.05},
  {"Alpha Hydri",             1.97970,  -61.5697,  2.86,  0.28},
  {"Alpha Tucanae",          22.30840,  -60.2597,  2.86,  1.39},
  {"Gamma Trianguli Australis", 15.31518, -68.6794, 2.89, 0.01},
  {"Epsilon Persei",          3.96431,   40.0103,  2.89, -0.18},
  {"Albaldah",               19.16272,  -21.0235,  2.89,  0.36},
  {"Sadalsuud",              21.52598,   -5.5712,  2.90,  0.83},
  {"Gamma Persei",            3.07996,   53.5064,  2.93,  0.70},
  {"Tau Puppis",              6.83208,  -50.6146,  2.94,  1.20},
  {"Sadalmelik",             22.09640,   -0.3199,  2.95,  0.98},
  {"Delta Corvi",            12.49778,  -16.5154,  2.95, -0.05},
  {"Upsilon Carinae",         9.78504,  -65.0720,  2.97,  0.27},
  {"Mebsuta",                 6.73224,   25.1311,  2.98,  1.38},
  {"Zeta Tauri",              5.62742,   21.1425,  3.00, -0.15},
  {"Gamma Hydrae",           13.31544,  -23.1716,  3.00,  0.92},
  {"Beta Trianguli",          2.15943,   34.9873,  3.00,  0.14},
  {"Gamma Gruis",            21.89880,  -37.3648,  3.00, -0.11},
  {"Epsilon Corvi",          12.16829,  -22.6197,  3.00,  1.33},
  {"Delta Persei",            3.71543,   47.7877,  3.01, -0.13},
  {"Epsilon Aurigae",         5.03215,   43.8233,  3.03,  0.54},
  {"Seginus",                14.53459,   38.3082,  3.03,  0.19},
  {"Gamma Ursae Minoris",    15.34547,   71.8340,  3.05,  0.05},
  {"Albireo",                19.51202,   27.9597,  3.05,  1.13},
  {"Dabih",                  20.35019,  -14.7814,  3.05,  0.79},
  {"Beta Muscae",            12.77213,  -68.1082,  3.05, -0.18},
  {"Mu Ursae Majoris",       10.37216,   41.4996,  3.05,  1.59},
  {"Delta Draconis",         19.20903,   67.6615,  3.07,  1.00},
  {"Beta Columbae",           5.84930,  -35.7683,  3.12,  1.16},
  {"Delta Herculis",         17.25054,   24.8395,  3.12,  0.08},
  {"Alpha Lyncis",            9.35090,   34.3925,  3.14,  1.55},
  {"Iota Ursae Majoris",      8.98583,   48.0417,  3.14,  0.19},
  {"Pi Herculis",            17.25054,   36.8092,  3.16,  1.44},
  {"Eta Aurigae",             5.10831,   41.2340,  3.17, -0.18},
  {"Theta Ursae Majoris",     9.54932,   51.6773,  3.17,  0.46},
  {"Zeta Draconis",          17.14653,   65.7147,  3.17, -0.12},
  {"Epsilon Leporis",         5.09155,  -22.3714,  3.19,  1.46},
  {"Alfirk",                 21.47764,   70.5607,  3.23, -0.22},
  {"Gamma Lyrae",            18.98240,   32.6896,  3.24, -0.05},
  {"Gamma Hydri",             3.78633,  -74.2390,  3.24,  1.60},
  {"Skat",                   22.91084,  -15.8208,  3.27,  0.05},
  {"Delta Andromedae",        0.65544,   30.8608,  3.27,  1.28},
  {"Alpha Doradus",           4.56687,  -55.0450,  3.27, -0.10},
  {"Propus",                  6.24853,   22.5068,  3.28,  1.60},
  {"Omega Carinae",          10.22939,  -70.0381,  3.29, -0.08},
  {"Iota Draconis",          15.41551,   58.9660,  3.29,  1.17},
  {"Beta Phoenicis",          1.10140,  -46.7189,  3.31,  0.89},
  {"Delta Ursae Majoris",    12.25706,   57.0326,  3.31,  0.08},
  {"Heze",                   13.57847,   -0.5958,  3.38,  0.11},
  {"Auva",                   12.92667,    3.3975,  3.38,  1.58},
  {"Ruchbah",                 1.43022,   60.2353,  2.68,  0.13},
  {"Segin",                   1.90659,   63.6701,  3.38, -0.15},
  {"Theta2 Tauri",            4.47740,   15.8709,  3.40,  0.18},
  {"Alpha Trianguli",         1.88529,   29.5793,  3.41,  0.49},
  {"Beta Lyrae",             18.83466,   33.3627,  3.45,  0.00},
  {"Nekkar",                 15.03219,   40.3906,  3.49,  0.95},
  {"Beta Cancri",             8.27510,    9.1856,  3.52,  1.48},
  {"Ain",                     4.47694,   19.1804,  3.53,  1.01},
  {"Wasat",                   7.33538,   21.9823,  3.53,  0.37},
  {"Eta Herculis",           16.71463,   38.9223,  3.53,  0.92},
  {"Alpha Capricorni",       20.30089,  -12.5445,  3.57,  0.91},
  {"Epsilon Crucis",         12.35648,  -60.4011,  3.59,  1.42},
  {"Zavijava",               11.84493,    1.7647,  3.59,  0.55},
  {"Atlas",                   3.81948,   24.0534,  3.63, -0.09},
  {"Eta Piscium",             1.52469,   15.3459,  3.62,  0.97},
  {"Thuban",                 14.07315,   64.3758,  3.65, -0.05},
  {"Gamma Tauri",             4.32989,   15.6276,  3.65,  0.99},
  {"Electra",                 3.74794,   24.1133,  3.70, -0.11},
  {"Alshain",                19.92189,    6.4068,  3.71,  0.86},
  {"Delta Tauri",             4.38182,   17.5425,  3.76,  0.98},
  {"Mekbuda",                 7.06862,   20.5703,  3.79,  0.79},
  {"Alrescha",                2.03349,    2.7638,  3.82,  0.32},
  {"Maia",                    3.76292,   24.3675,  3.87, -0.07},
  {"Mesarthim",               1.89216,   19.2939,  3.88,  0.02},
  {"Delta Cancri",            8.74478,   18.1543,  3.94,  1.08},
  {"Syrma",                  14.26805,   -6.0006,  4.07,  0.51},
  {"Alkes",                  10.99622,  -18.2988,  4.07,  1.08},
  {"Merope",                  3.77192,   23.9483,  4.14, -0.06},
  {"Acubens",                 8.97479,   11.8577,  4.25,  0.14},
  {"Taygeta",                 3.75333,   24.4672,  4.30, -0.11}
}

-- The galactic pole in J2000 equatorial coordinates. `star_field` uses it to
-- concentrate the procedural faint stars and the Milky Way's glow toward the
-- galactic plane, which is where they are: the faint sky is not uniform, it is
-- a disc seen from inside.
catalog.galacticPole = {
  rightAscension = 12.85644 * math.pi / 12.0,   -- 12h 51m 26s
  declination = 27.12825 * math.pi / 180.0      -- +27 deg 07' 42"
}

-- Galactic longitude of the ascending node of the galactic plane on the J2000
-- equator, used to place the galactic centre so the Milky Way is brightest in
-- Sagittarius rather than at an arbitrary longitude.
catalog.galacticCentre = {
  rightAscension = 17.7611 * math.pi / 12.0,    -- 17h 45m 40s
  declination = -29.0078 * math.pi / 180.0      -- -29 deg 00' 28"
}

-- Unit vector in J2000 equatorial coordinates.
function catalog.unitVector(rightAscensionHours, declinationDegrees)
  local ra = rightAscensionHours * math.pi / 12.0
  local dec = declinationDegrees * math.pi / 180.0
  local cosDec = math.cos(dec)
  return cosDec * math.cos(ra), cosDec * math.sin(ra), math.sin(dec)
end

return catalog
