gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

local font = resource.load_font "font.ttf"
local logo = resource.load_image "logo.png"

-- Couleurs E.Leclerc (approximatives)
local BLEU   = {0.00, 0.36, 0.67}
local ORANGE = {0.97, 0.58, 0.12}
local BLANC  = {1, 1, 1}
local GRIS   = {0.93, 0.94, 0.96}

local tex_blanc  = resource.create_colored_texture(1, 1, 1, 1)
local tex_orange = resource.create_colored_texture(ORANGE[1], ORANGE[2], ORANGE[3], 1)
local tex_bleu   = resource.create_colored_texture(BLEU[1], BLEU[2], BLEU[3], 1)
local tex_gris   = resource.create_colored_texture(GRIS[1], GRIS[2], GRIS[3], 1)

-- Disque ou anneau lisse, dessine par un shader (pas d'image necessaire)
local shader_disque = resource.create_shader[[
  #ifdef GL_ES
  precision mediump float;
  #endif
  uniform sampler2D Texture;
  varying vec2 TexCoord;
  uniform float interieur;
  uniform float flou;
  uniform float r, g, b;
  void main() {
    float d = length(TexCoord - vec2(0.5)) * 2.0;
    float a = (1.0 - smoothstep(1.0 - flou, 1.0, d)) * smoothstep(interieur - flou, interieur, d);
    gl_FragColor = texture2D(Texture, TexCoord) * vec4(r, g, b, a);
  }
]]

local JOURS = {"DIM","LUN","MAR","MER","JEU","VEN","SAM"}
local MOIS  = {"JANVIER","FÉVRIER","MARS","AVRIL","MAI","JUIN","JUILLET",
               "AOÛT","SEPTEMBRE","OCTOBRE","NOVEMBRE","DÉCEMBRE"}

-- Reglages (modifiables depuis le tableau de bord info-beamer)
local trotteuse = true
local fluide    = false

util.json_watch("config.json", function(config)
  if config.trotteuse ~= nil then trotteuse = config.trotteuse end
  fluide = config.mouvement == "fluide"
end)

-- Heure d'été européenne automatique (France)
local function jour_semaine(y, m, d)   -- 0 = dimanche
  local t = {0,3,2,5,0,3,5,2,6,4,2,4}
  if m < 3 then y = y - 1 end
  return (y + math.floor(y/4) - math.floor(y/100) + math.floor(y/400) + t[m] + d) % 7
end

local function decalage(utc)
  local debut = 3 * 10000 + (31 - jour_semaine(utc.year, 3, 31)) * 100 + 1
  local fin   = 10 * 10000 + (31 - jour_semaine(utc.year, 10, 31)) * 100 + 1
  local now   = utc.month * 10000 + utc.day * 100 + utc.hour
  if now >= debut and now < fin then return 7200 end
  return 3600
end

-- Fraction de seconde pour la trotteuse fluide
local derniere_seconde, debut_seconde = 0, 0
local function fraction_seconde(t)
  if t ~= derniere_seconde then
    derniere_seconde, debut_seconde = t, sys.now()
  end
  return math.min(sys.now() - debut_seconde, 0.999)
end

local function disque(cx, cy, rayon, c, interieur)
  shader_disque:use{
    interieur = interieur or 0,
    flou = 1.5 / rayon,
    r = c[1], g = c[2], b = c[3],
  }
  tex_blanc:draw(cx - rayon, cy - rayon, cx + rayon, cy + rayon)
  shader_disque:deactivate()
end

-- Rectangle tourne autour du centre du cadran (angle en degres, 0 = midi)
-- de "debut" a "fin" le long du rayon (negatif = cote oppose)
local function trait(cx, cy, angle, debut, fin, largeur, tex)
  gl.pushMatrix()
  gl.translate(cx, cy)
  gl.rotate(angle, 0, 0, 1)
  tex:draw(-largeur / 2, -fin, largeur / 2, -debut)
  gl.popMatrix()
end

local function centre(texte, x, y, taille, c)
  local w = font:width(texte, taille)
  font:write(x - w / 2, y - taille / 2, texte, taille, c[1], c[2], c[3], 1)
end

local function cadran(cx, cy, R)
  -- Lunette orange, face blanche
  disque(cx, cy, R, ORANGE)
  disque(cx, cy, R * 0.95, BLANC)

  -- Graduations : minutes fines, heures epaisses
  for i = 0, 59 do
    if i % 5 == 0 then
      trait(cx, cy, i * 6, R * 0.80, R * 0.91, R * 0.022, tex_bleu)
    else
      trait(cx, cy, i * 6, R * 0.87, R * 0.91, R * 0.007, tex_bleu)
    end
  end

  -- Chiffres (le 3 laisse la place au guichet jour/date, comme sur une montre)
  for h = 1, 12 do
    if h ~= 3 then
      local a = math.rad(h * 30)
      centre(tostring(h), cx + math.sin(a) * R * 0.68, cy - math.cos(a) * R * 0.68,
             R * 0.15, BLEU)
    end
  end
end

local function logo_cadran(cx, cy, R)
  local iw, ih = logo:size()
  local lw = R * 0.62
  local lh = lw * ih / iw
  local y  = cy - R * 0.36 - lh / 2
  logo:draw(cx - lw / 2, y, cx + lw / 2, y + lh)
end

-- Guichet a 3 heures : jour en orange, quantieme en bleu
local function guichet(cx, cy, R, d)
  local jour  = JOURS[d.wday]
  local date  = tostring(d.day)
  local taille = R * 0.11
  local espace = font:width(" ", taille)
  local w = font:width(jour, taille) + espace + font:width(date, taille)
  local pad = R * 0.035
  local x2 = cx + R * 0.76
  local x1 = x2 - w - pad * 2
  local y1, y2 = cy - taille / 2 - pad, cy + taille / 2 + pad
  local bord = R * 0.012

  tex_bleu:draw(x1 - bord, y1 - bord, x2 + bord, y2 + bord)
  tex_gris:draw(x1, y1, x2, y2)

  local x = x1 + pad
  font:write(x, cy - taille / 2, jour, taille, ORANGE[1], ORANGE[2], ORANGE[3], 1)
  x = x + font:width(jour, taille) + espace
  font:write(x, cy - taille / 2, date, taille, BLEU[1], BLEU[2], BLEU[3], 1)
end

local function aiguilles(cx, cy, R, d, frac)
  local s = d.sec + frac
  local m = d.min + s / 60
  local h = (d.hour % 12) + m / 60

  trait(cx, cy, h * 30, -R * 0.10, R * 0.50, R * 0.055, tex_bleu)
  trait(cx, cy, m * 6,  -R * 0.12, R * 0.78, R * 0.035, tex_bleu)
  disque(cx, cy, R * 0.06, BLEU)

  if trotteuse then
    trait(cx, cy, s * 6, -R * 0.20, R * 0.86, R * 0.012, tex_orange)
    disque(cx, cy, R * 0.035, ORANGE)
  end
end

function node.render()
  gl.clear(BLEU[1], BLEU[2], BLEU[3], 1)

  -- Bandeaux orange haut et bas
  tex_orange:draw(0, 0, WIDTH, HEIGHT * 0.03)
  tex_orange:draw(0, HEIGHT * 0.97, WIDTH, HEIGHT)

  -- Heure locale
  local t   = os.time()
  local utc = os.date("!*t", t)
  local d   = os.date("!*t", t + decalage(utc))
  local frac = fluide and fraction_seconde(t) or 0

  -- Le cadran occupe toute la hauteur entre les bandeaux
  local cx, cy = WIDTH / 2, HEIGHT / 2
  local R = math.min(HEIGHT * 0.455, WIDTH * 0.48)

  cadran(cx, cy, R)
  logo_cadran(cx, cy, R)
  guichet(cx, cy, R, d)
  centre(MOIS[d.month] .. " " .. d.year, cx, cy + R * 0.36, R * 0.075, BLEU)
  aiguilles(cx, cy, R, d, frac)
end
