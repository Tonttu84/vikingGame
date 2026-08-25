class_name UIPalette
extends RefCounted
## The one palette, everywhere (tech-plan: consistency reads as art
## direction). Parchment, sea-dark blue, blood-red, iron-grey, gold —
## no other colors.

const SEA_DARK := Color("16222e")        ## app background
const SEA := Color("1f3242")             ## player half of the deck
const SEA_LIGHT := Color("2b4358")       ## panels, hovers
const IRON_DARK := Color("2e3438")       ## enemy half of the deck
const IRON := Color("6e7378")            ## enemy trim, disabled text
const PARCHMENT := Color("e8d8b0")       ## primary text, card faces
const PARCHMENT_DIM := Color("b7a983")   ## secondary text
const BLOOD := Color("8c2b2b")           ## HP, damage, enemy captain
const GOLD := Color("c9a227")            ## momentum, player trim, highlights

const FONT_BODY := 13
const FONT_SMALL := 11
const FONT_TITLE := 17


static func panel(bg: Color, border: Color = Color.TRANSPARENT, border_width := 0,
		radius := 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(border_width)
	style.border_color = border
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(8)
	return style


static func bar_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(3)
	return style


static func label(text: String, size := FONT_BODY, color := PARCHMENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
