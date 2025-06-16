--- @type fun(name: string, argName: string, arg: any, expectType: string, nilOk: boolean): nil
local checkTypeForNamedArg = require('libraryUtil').checkTypeForNamedArg

-------------------------------------------------------------------------------
-- Status class
-------------------------------------------------------------------------------

--- @class StatusOptions
--- @field prefix string
--- @field color string
--- @field text string
--- @field subtext string?

--- Object mapping from status option keys to a boolean indicating whether they can be `nil`.
--- @type table<string, boolean>
local typeMap = {
	prefix = false,
	color = false,
	text = false,
	subtext = true
}

--- @class Status
--- @field _options StatusOptions
local Status = {}
Status.__index = Status

--- Gets the default status options.
--- @return StatusOptions
--- @static
function Status.getDefaultOptions()
	--- @type StatusOptions
	return {
		prefix = '状態',
		color = '#CCC',
		text = '処理中'
	}
end

--- Merges the default status options with user-defined options.
--- @param name string Name of the calling function, used in error messages.
--- @param options table? Partial table of StatusOptions.
--- @param defaults table? Optional fallback values. Defaults to `getDefaultOptions()`.
--- @return StatusOptions
--- @static
function Status.merge(name, options, defaults)

	options = options or {}
	defaults = defaults or Status.getDefaultOptions()

	--- @type StatusOptions
	local mergedOptions = {
		prefix = options.prefix or defaults.prefix,
		color = options.color or defaults.color,
		text = options.text or defaults.text,
		subtext = options.subtext or defaults.subtext
	}

	--- A clone of `typeMap` object, mapping from required property keys to `false`.
	--- The boolean value is set to `true` when the corresponding property is found in `mergedOptions`.
	local requiredProps = {}
	for k, v in pairs(typeMap) do
		local isRequired = v == false
		if isRequired then
			requiredProps[k] = false
		end
	end

	-- Check types, ensuring all required properties are present
	for k, v in pairs(mergedOptions) do
		local nilOk = typeMap[k]
		if nilOk ~= nil then
			checkTypeForNamedArg(name, 'options.' .. k, v, 'string', nilOk)
			if requiredProps[k] ~= nil then
				requiredProps[k] = true
			end
		end
	end

	-- Throw an error if any required property is missing in `mergedOptions`
	for k, wasSet in pairs(requiredProps) do
		if not wasSet then
			error(string.format('Property "%s" is required for StatusOptions.', k))
		end
	end

	return mergedOptions
end

--- Creates a new Status instance.
--- @param options table Partial StatusOptions. Missing fields will be filled with defaults.
--- @return Status
--- @constructor
function Status.new(options)
	local self = setmetatable({}, Status)
	self._options = Status.merge('Status.new', options)
	return self
end

--- Gets the prefix string.
--- @return string
function Status:getPrefix()
	return self._options.prefix
end

--- Sets the prefix string.
--- @param prefix string
--- @return self
function Status:setPrefix(prefix)
	checkTypeForNamedArg('Status:setPrefix', 'prefix', prefix, 'string', false)
	self._options.prefix = prefix
	return self
end

--- Gets the color string.
--- @return string
function Status:getColor()
	return self._options.color
end

--- Sets the color string.
--- @param color string
--- @return self
function Status:setColor(color)
	checkTypeForNamedArg('Status:setColor', 'color', color, 'string', false)
	self._options.color = color
	return self
end

--- Gets the main status text.
--- @return string
function Status:getText()
	return self._options.text
end

--- Sets the main status text.
--- @param text string
--- @return self
function Status:setText(text)
	checkTypeForNamedArg('Status:setText', 'text', text, 'string', false)
	self._options.text = text
	return self
end

--- Gets the subtext, or `nil` if not set.
--- @return string?
function Status:getSubtext()
	return self._options.subtext
end

--- Sets the subtext string. If `nil` is given, the property will be reset.
--- @param subtext string?
--- @return self
function Status:setSubtext(subtext)
	checkTypeForNamedArg('Status:setSubtext', 'subtext', subtext, 'string', true)
	self._options.subtext = subtext
	return self
end

--- Returns a copy of the current options table.
--- @return StatusOptions
function Status:getOptions()
	local ret = {}
	for k, v in pairs(self._options) do
		ret[k] = v
	end
	return ret
end

--- Sets new options, with optional reset of defaults.
--- @param options table Partial StatusOptions.
--- @param flush boolean? If `true`, discard current values and use only the new ones.
--- @return self
function Status:setOptions(options, flush)
	local defaults = flush and {} or nil
	self._options = Status.merge('Status:setOptions', options, defaults)
	return self
end

--- Converts the status to an HTML representation.
--- @diagnostic disable-next-line: undefined-doc-name
--- @return mw.html
function Status:toHtml()
	return mw.html.create('div')
		:css({ display = 'flex', ['align-content'] = 'center' })
		:wikitext(self._options.prefix .. ':&nbsp;')
		:tag('span')
			:css('background', self._options.color)
			:wikitext('&emsp;&emsp;')
			:done()
		:wikitext('&nbsp;')
		:tag('b')
			:wikitext(self._options.text)
			:done()
		:wikitext(
			self._options.subtext
			and string.format('（%s）', self._options.subtext)
			or ''
		)
end

--- Converts the status to a string by rendering the HTML.
--- @return string
function Status:toString()
	return tostring(self:toHtml())
end

function Status:__tostring()
	return tostring(self:toHtml())
end

-------------------------------------------------------------------------------
-- Package function
-------------------------------------------------------------------------------

--- Removes certain invisible UTF-8 characters and trims whitespace.
--- @param str string Input string.
--- @return string Cleaned string.
local function clean(str)
	return str:gsub('\226\128[\142\170\172]', ''):match('^%s*(.-)%s*$')
end

--- Returns the input string, or `nil` if the input (trimmed of leading and trailing whitespace) is an empty string.
--- @param str string
--- @return string?
local function nilIfEmpty(str)
	str = clean(str)
	if str == '' then
		return nil
	end
	return str
end

local statusMap = {
	alias = {
		done = 'done',
		d = 'done',
		['+'] = 'done',
		['対処'] = 'done',
		['済'] = 'done',

		notdone = 'notdone',
		nd = 'notdone',
		['-'] = 'notdone',
		['却下'] = 'notdone',
		['見送り'] = 'notdone',
		['非対処'] = 'notdone',

		cannot = 'cannot',
		['対処不可'] = 'cannot',
		['不可'] = 'cannot',

		complete = 'complete',
		c = 'complete',
		['完了'] = 'complete',

		onhold = 'onhold',
		oh = 'onhold',
		hold = 'onhold',
		['?'] = 'onhold',
		['保留'] = 'onhold',

		withdrawn = 'withdrawn',
		w = 'withdrawn',
		['取り下げ'] = 'withdrawn',

		redundant = 'redundant',
		r = 'redundant',
		['重複'] = 'redundant',

		alreadydone = 'alreadydone',
		ad = 'alreadydone',
		['既対処'] = 'alreadydone'
	},
	color = {
		done = '#0C0',
		notdone = '#C00',
		cannot = '#FFD700',
		complete = '#00BFFF',
		onhold = '#F88000',
		withdrawn = '#000088',
		redundant = '#F99',
		alreadydone = '#000000',
	},
	text = {
		done = '対処済み',
		notdone = '対処せず',
		cannot = '対処不可',
		complete = '完了',
		onhold = '保留',
		withdrawn = '取り下げ',
		redundant = '重複',
		alreadydone = '既対処',
	}
}

local function main(frame)
	local args = frame.args
	local statusArg = string.lower(args.status):gsub('[_%s]', '')
	local status = statusMap.alias[statusArg] or ''
	local options = {
		prefix = nilIfEmpty(args.prefix),
		color = statusMap.color[status],
		text = nilIfEmpty(args.text) or statusMap.text[status],
		subtext = nilIfEmpty(args.subtext)
	}
	return Status.new(options):toString()
end

return {
	Status = Status,
	main = main
}