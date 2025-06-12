local p = {}

--- Map of action keywords to corresponding icon wikitext.
local iconMap = {
	open = '[[File:Antu google-keep.svg|20px]] ',
	keep = '[[File:Action lock 2 - gray.svg|15px]] ',
	undo = '[[File:Action unlock 2 - green.svg|15px]] '
}

--- Encloses a string with a sequence of HTML tags, from outermost to innermost.
--- @param str string The string to wrap in tags.
--- @param tagNames string[] An array of tag names to wrap the string with.
--- @return string The tag-enclosed string.
local function enclose(str, tagNames)
	for i = #tagNames, 1, -1 do
		local tag = tagNames[i]
		str = string.format('<%s>%s</%s>', tag, str, tag)
	end
	return str
end

--- Constructs a formatted error message in HTML.
--- @param key string Parameter key name.
--- @param value unknown The invalid parameter value.
--- @return string HTML-formatted error message.
local function createError(key, value)
	local err = mw.html.create('strong')
		:attr('class', 'error')
		:wikitext(string.format(
			'[[Template:AbuseLog]]エラー: 不正な%s引数: "%s"%s',
			enclose('|' .. key .. '=', { 'code' }),
			tostring(value),
			'[[Category:テンプレート呼び出しエラーのあるページ/Template:AbuseLog]]'
		))
	return tostring(err)
end

--- Returns a formatted AbuseLog link with an appropriate icon, or a static icon string.
--- @param logidOrIcon string Either a numeric log ID or a keyword like "継続", "解除", etc.
--- @param action string Expected action ("継続", "解除", or "") when a log ID is provided.
--- @return string Wikitext for the AbuseLog link or icon.
local function getLinkOrIcon(logidOrIcon, action)
	local id = tonumber(logidOrIcon)
	if id then
		local iconType = (action == '') and 'open'
			or (action == '継続') and 'keep'
			or (action == '解除') and 'undo'
		if not iconType then
			return createError('2', action)
		end

		local label = (action ~= '') and (enclose(action, { 'small', 'b' }) .. ' ') or ''
		return string.format(
			'%s%s[[特別:不正利用記録/%d|不正利用記録/%d]]',
			iconMap[iconType],
			label,
			id,
			id
		)
	end

	-- Handle static keyword case
	local keywordMap = {
		['継続']  = { icon = 'keep', tag = 'b' },
		['継続r'] = { icon = 'keep', tag = 's' },
		['解除']  = { icon = 'undo', tag = 'b' },
		['解除r'] = { icon = 'undo', tag = 's' }
	}

	local entry = keywordMap[logidOrIcon]
	if entry then
		local label = logidOrIcon:gsub('r$', '') -- Remove trailing 'r' if present
		return iconMap[entry.icon] .. enclose(label, { entry.tag })
	end

	return createError('1', logidOrIcon)
end

--- Removes certain invisible UTF-8 characters and trims whitespace.
--- @param str string Input string.
--- @return string Cleaned string.
local function clean(str)
	return str:gsub('\226\128[\142\170\172]', ''):match('^%s*(.-)%s*$')
end

--- Entry point for the module, called from the template.
--- @param frame table Frame object from MediaWiki.
--- @return string Wikitext to display.
function p.main(frame)
	local args = frame.args
	local logidOrIcon = clean(args['1'] or '')
	local action = clean(args['2'] or '')
	return getLinkOrIcon(logidOrIcon, action)
end

return p
