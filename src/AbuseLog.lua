local Status = require('Module:Status').Status;

--- Constructs a formatted error message in HTML.
--- @param key string Parameter key name.
--- @param value unknown The invalid parameter value.
--- @return string HTML-formatted error message.
local function createError(key, value)
	local err = mw.html.create('strong')
		:attr('class', 'error')
		:wikitext(string.format(
			'[[Template:AbuseLog]]エラー: 不正な<code>%s</code>引数: "%s"%s',
			'|' .. key .. '=',
			tostring(value),
			'[[Category:テンプレート呼び出しエラーのあるページ/Template:AbuseLog]]'
		))
	return tostring(err)
end

--- Validates whether the `id` parameter is a number.
--- @param id string The ID value to validate.
--- @return string Validated ID if valid.
--- @return string? HTML error string if invalid.
local function validateId(id)
	if string.match(id, '^%d+$') then
		return id
	end
	return id, createError('id', id)
end

local WEEKDAYS = { '日', '月', '火', '水', '木', '金', '土' }

--- Checks whether the input is a valid Japanese weekday.
--- @param weekday string? The weekday to validate.
--- @return boolean
local function isValidWeekday(weekday)
	if type(weekday) ~= 'string' then
		return false
	end
	for _, v in ipairs(WEEKDAYS) do
		if weekday == v then
			return true
		end
	end
	return false
end

--- Validates and parses a `deadline` string in the expected Japanese format.
--- Accepted format: "YYYY年M月D日 (曜) HH:MM (UTC)"
--- @param deadline string Deadline string.
--- @return string Validated deadline string if valid.
--- @return string? HTML error string if invalid.
local function validateDealine(deadline)

	local year, month, day, weekday, hour, min =
		string.match(deadline, '^(%d%d%d%d)年(%d%d?)月(%d%d?)日 %(([^%)]+)%) (%d%d):(%d%d) %(UTC%)$')

	if year and isValidWeekday(weekday) then
		year = assert(tonumber(year))
		month = assert(tonumber(month))
		day = assert(tonumber(day))
		hour = assert(tonumber(hour))
		min = assert(tonumber(min))

		local isValid =
			year >= 2000 and year <= 2100 and
			month >= 1 and month <= 12 and
			day >= 1 and day <= 31 and  -- Simplified, doesn't check days-per-month or leap years
			hour >= 0 and hour <= 23 and
			min >= 0 and min <= 59

		if isValid then
			return deadline
		end
	end

	return deadline, createError('deadline', deadline)
end

local UNBLOCK_AT = '%s に自動解除'
local STRIPE = 'repeating-linear-gradient(140deg, %s, %s 5px, transparent 5px, transparent 9px)'

--- Returns a CSS gradient string with a striped pattern using the given color.
--- The same color is used for both starting and ending points of the stripe.
--- @param color string A string representing the CSS color (e.g., "#ccc" or "red").
--- @return string A string representing a CSS `repeating-linear-gradient`.
local function getStripeColor(color)
	return string.format(STRIPE, color, color)
end

local statusMap = {
	alias = {
		[''] = 'reviewing',

		done = 'done',
		d = 'done',
		['継続'] = 'done',

		unblock = 'unblock',
		ub = 'unblock',
		['解除'] = 'unblock',

		['unblocked-bot'] = 'unblocked-bot',

		['unblocked-manual'] = 'unblocked-manual',

		modified = 'modified',

		onhold = 'onhold',
		oh = 'onhold',
		['保留'] = 'onhold'
	},
	options = {
		reviewing = {
			color = '#CCC',
			text = '審査中',
			subtext = UNBLOCK_AT
		},
		done = {
			color = '#0C0',
			text = '継続'
		},
		unblock = {
			color = getStripeColor('#FFD700'),
			text = '解除予約'
		},
		['unblocked-bot'] = {
			color = '#FFD700',
			text = '解除済'
		},
		['unblocked-manual'] = {
			color = '#F99',
			text = '手動解除済'
		},
		modified = {
			color = '#00BFFF',
			text = '再ブロック済'
		},
		onhold = {
			color = '#F88000',
			text = '保留'
		}
	}
}

--- Validates and resolves the `status` parameter using the status map.
--- @param status string Status alias or key.
--- @return table Table of status options if valid.
--- @return string? HTML error string if invalid.
local function validateStatus(status)
	local key = statusMap.alias[status]
	if key then
		return statusMap.options[key]
	end
	return {}, createError('status', status)
end

--- Removes certain invisible UTF-8 characters and trims whitespace.
--- @param str string Input string.
--- @return string Cleaned string.
local function clean(str)
	return str:gsub('\226\128[\142\170\172]', ''):match('^%s*(.-)%s*$')
end

--- Entry point for the template logic. Validates parameters and returns formatted HTML.
--- This function is meant to be invoked from a #invoke call in a Lua module frame.
--- @param frame table The Scribunto frame object passed to the module.
--- @return string Rendered HTML string or error message.
local function main(frame)
	local args = frame.args
	for k, v in pairs(args) do
		args[k] = clean(v)
	end

	local id, idErr = validateId(args.id)
	if idErr then return idErr end
	local deadline, dlErr = validateDealine(args.deadline)
	if dlErr then return dlErr end
	local options, stErr = validateStatus(args.status)
	if stErr then return stErr end

	local status = Status.new(options)
	local subtext = status:getSubtext()
	if subtext then
		status:setSubtext(string.format(subtext, deadline))
	end

	local abuselog = mw.html.create('ul')
		:tag('li')
			:wikitext(string.format('[[特別:不正利用記録/%d|不正利用記録/%d]]', id, id))
			:allDone()

	return tostring(status) .. tostring(abuselog)
end

return {
	main = main
}