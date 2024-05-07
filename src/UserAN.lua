local verifyIp = require('Module:IP').Util.isIPAddress

-----------------------
--- HELPER FUNCTIONS
-----------------------

---Check if the first argument is identical to any of the following ones.
---@param comparator any
---@param ... unknown
---@return boolean
local function equalsToAny(comparator, ...)
	for _, v in ipairs(arg) do
		if comparator == v then return true end
	end
	return false
end

---Remove unicode bidirectional markers from a string and trim it.
---@param str string
---@return string
local function clean(str)
	str = str:gsub('\226\128[\142\170\172]', ''):match('^[%s_]*(.-)[%s_]*$')
	return str
end

-----------------------
--- MAIN FUNCTIONS
-----------------------

---Create an icon as wikitext.
---@param icon 'done'|'doing'|'notdone'|'alreadydone'
---@param text string?
---@return string
local function createIcon(icon, text)
	-- Note: [[Module:SockInfo2]] searches for '<span class="doing">', and if there's any,
	-- the module thinks that UserANs in it are NOT all processed. This means that the structure
	-- of '<span class="doing">' should never be altered.
	local base
	if icon == 'done' then
		base = '[[File:Yes_check.svg|20px|<span class="done">対処済み</span>]]%s'
	elseif icon == 'doing' then
		base = '[[File:Stock_post_message.svg|22px|<span class="doing">未対処</span>]]%s'
	elseif icon == 'notdone' then
		base = '[[File:X_mark.svg|20px|<span class="notdone">対処せず</span>]]%s'
	else
		base = '[[File:Black_check.svg|20px|<span class="alreadydone">既に対処済み</span>]]%s'
	end
	return string.format(base, text and string.format(' <small><b>%s</b></small> ', text) or ' ')
end

---Get an icon for the template.
---@param autostatus string The value of `2=` parameter; should be in lowercase.
---@param manualstatus string The value of `状態=` parameter.
---@return string
local function getIcon(autostatus, manualstatus)
	if autostatus == '' then
		if manualstatus == '' then
			return createIcon('doing')
		else
			return createIcon('done')
		end
	elseif equalsToAny(autostatus, 'done', '済', '済み') then
		return createIcon('done', '済み')
	elseif equalsToAny(autostatus, 'not done', '却下', '非対処') then
		return createIcon('notdone', '却下')
	elseif equalsToAny(autostatus, '取り下げ', '見送り') then
		return createIcon('notdone', autostatus)
	else
		local nd = autostatus:match('^%$nd(.+)$')
		local ad = autostatus:match('^%$ad(.+)$')
		if nd then
			return createIcon('notdone', nd)
		elseif ad then
			return createIcon('alreadydone', ad)
		else
			return createIcon('done', autostatus)
		end
	end
end

---Get the main text of the UserAN template.
---@param reportee string All underlines should have been replaced with spaces.
---@param linkType 'user2'|'unl'|'ip2'|'ip2cidr'|'logid'|'diffid'|'none'
---@return string
local function getText(reportee, linkType)

	-- Variables with the non-underscored reportee
	local unl = '利用者:' .. reportee
	local user = '[[' .. unl .. ']]'
	local ip = 'IP:' .. reportee
	local none = reportee

	-- Variables with an underscored reportee
	reportee = reportee:gsub(' ', '_')
	local talk = '[[User_talk:%s|会話]]'
	local contribs = '[[Special:Contributions/%s|投稿記録]]'
	local log = '[//ja.wikipedia.org/w/index.php?title=Special:Log&page=User:%s 記録]'
	local filterLog = '[//ja.wikipedia.org/w/index.php?title=Special:AbuseLog&wpSearchUser=%s フィルター記録]'
	local ca = '[[Special:CentralAuth/%s|CA]]'
	local guc = '[//xtools.wmflabs.org/globalcontribs/ipr-%s GUC]'
	local st = '[//meta.toolforge.org/stalktoy/%s ST]'
	local spur = '[//spur.us/context/%s SPUR]'
	local block = '[[Special:Block/%s|ブロック]]'
	local logid = '[[Special:Redirect/logid/%s|Logid/%s]]'
	local diffid = '[[Special:Diff/%s|差分/%s]]の投稿者'

	-- Define the main text as a string, and auxiliary links as a string array
	local text, links
	if linkType == 'unl' then
		text = unl
		links = {talk, contribs, log, filterLog, ca, block}
	elseif linkType == 'ip2' then
		text = ip
		links = {talk, contribs, log, filterLog, spur, guc, st, block}
	elseif linkType == 'ip2cidr' then
		text = ip
		links = {talk, contribs, log, guc, st, block}
	elseif linkType == 'logid' then
		text = logid
		links = {}
	elseif linkType == 'diffid' then
		text = diffid
		links = {}
	elseif linkType == 'none' then
		text = none
		links = {}
	else
		text = user
		links = {talk, contribs, log, filterLog, ca, block}
	end

	-- Stringify the auxiliary links, if any
	if #links > 0 then
		text = text .. ' <span class="plainlinks" style="font-size:smaller;">('
		text = text .. table.concat(links, ' / ')
		text = text .. ')</span>'
	end
	text = text:gsub('%%s', reportee)

	return text

end

---@class Error
---@field suppress boolean
---@field list string[]
---@field texts string[]
local Error = {}
Error.__index = Error

---Initialize an Error instance.
---@param suppress boolean? Whether to suppress errors, if any
function Error.new(suppress)
	local self = setmetatable({}, Error)
	self.suppress = not not suppress
	self.list = {}
	self.texts = {
		nousername = '第一引数は必須です',
		nonipexpected = '「type=%s」に対しIPアドレスが指定されています', -- $1: type param value
		ipexpected = '「type=%s」には有効なIPアドレスを指定してください', -- $1: type param value
		invalidcidr = '「%s」は無効なIPサブネットです', -- $1: invalid cidr
		numberexpected = '「type=%s」には数字を指定してください', -- $1: type param value
		invalidtype = '「type=%s」は存在しません' -- $1: type param value
	}
	return self
end

---Add an error message.
---@param errorType "nousername"|"nonipexpected"|"ipexpected"|"invalidcidr"|"numberexpected"|"invalidtype"
---@param ... string Variables for `string.format`.
function Error:add(errorType, ...)
	---@diagnostic disable-next-line: deprecated
	table.insert(self.list, string.format(self.texts[errorType], unpack(arg)))
	return self
end

---Return error messages as a concatenated string for rendering.
---@param resetFontSize boolean? Optional parameter to undo the application of `font-size: smaller;`.
---@return string
function Error:render(resetFontSize)
	if #self.list > 0 and not self.suppress then
		return string.format(
			' <b style="color: red;%s>[[Template:UserAN|UserAN]]エラー: %s</b>%s',
			not resetFontSize and ' font-size: smaller;' or '',
			table.concat(self.list, '; '),
			'[[Category:テンプレート呼び出しエラーのあるページ/Template:UserAN]]'
		)
	else
		return ''
	end
end

-----------------------
--- PACKAGE FUNCTION
-----------------------

local p = {}

function p.Main(frame)

	local args = frame.args
	local u = clean(args.username)
	local t = clean(args.type)
	-- Add the error category (if relevant) only when called from Template:UserAN
	local err = Error.new(frame:getParent():getTitle() ~= 'Template:UserAN')

	-- Evaluate the username parameter
	if u == '' then
		return err:add('nousername'):render(true)
	else
		u = u:gsub('_', ' ')
	end

	-- Evaluate IP
	local isIp = verifyIp(u)
	local isCidr, _, corrected = verifyIp(u, true, true)
	corrected = corrected and corrected:upper()
	local isIPAddress = isIp or isCidr
	u = isIPAddress and u:upper() or u

	-- Evaluate the type parameter and add errors if any
	local linkType = string.lower(t) -- 'user2'|'unl'|'ip2'|'ip2cidr'|'logid'|'diffid'|'none'
	local typeMap = {
		[''] = isIPAddress and 'ip2' or 'user2', -- t=IP2 or t=User2 by default
		user2 = 'user2',
		usernolink = 'unl',
		unl = 'unl',
		ipuser2 = 'ip2',
		ip2 = 'ip2',
		log = 'logid',
		logid = 'logid',
		diff = 'diffid',
		diffid = 'diffid',
		none = 'none'
	}
	local isInvalid = false
	if typeMap[linkType] then
		linkType = typeMap[linkType]
	else -- Undefined type detected
		isInvalid = true
		err:add('invalidtype', t)
		linkType = 'unl'
	end
	if equalsToAny(linkType, 'logid', 'diffid') and not u:find('^%d+$') then -- if not a number
		err:add('numberexpected', t)
		linkType = 'unl'
	end
	if linkType == 'ip2' then
		if not isIPAddress then -- ip2 but a non-IP has been passed
			err:add('ipexpected', t)
			linkType = 'unl'
		elseif corrected then -- Cidr is provided but modified because it's invalid
			err:add('invalidcidr', u)
		end
	elseif isIPAddress then -- Not ip2 but an IP has been passed (doesn't meet this condition on t="")
		if not isInvalid then
			err:add('nonipexpected', t)
			if corrected then
				err:add('invalidcidr', u)
			end
		end
		linkType = 'ip2'
	end
	if linkType == 'ip2' and (isCidr or corrected) then
		linkType = 'ip2cidr' -- If the IP is a CIDR, modify the canonical type
	end

	-- Return the string to display
	return getIcon(string.lower(args.autostatus), args.manualstatus) .. getText(corrected or u, linkType) .. err:render()

end

return p