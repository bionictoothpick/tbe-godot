extends ObjectBehavior
## Post-it notes: click to read. Pages come from properties page1, page2, ...


func pages() -> Array:
	var out: Array = []
	var i := 1
	while TBE.prop(body.props, "page%d" % i) != null:
		out.append(TBE.html_to_bbcode(str(TBE.prop(body.props, "page%d" % i))))
		i += 1
	return out


func on_clicked_in_edit() -> bool:
	world.note_requested.emit(pages(), body.def.type_name)
	return true


func on_clicked() -> bool:
	return on_clicked_in_edit()
