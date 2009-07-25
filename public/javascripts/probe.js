function refresh() {
	$('#probe').load(String(window.location), null, refresh_callback)
}

function refresh_callback(responseText, textStatus, req) {
	if (req.status == '202')
		setTimeout(refresh, 1000)
}

$(window).load(function() {
	refresh()
})
