local IPUtil = require('Module:IP').Util
local yesno = require('Module:Yesno')

local p = {}

---@return string, boolean, string | nil
local function getArgs(frame)
	local args = frame.args
	local ipStr = args['1']
	if not ipStr then
		error('Argument #1 is required')
	end
	return ipStr, yesno(args['2'], false), args.fallback
end

---@param isValid boolean
---@param corrected string | nil
---@param fallback string | nil
---@return string
local function formatResult(isValid, corrected, fallback)
	if corrected then return corrected end
	return isValid and '1' or (fallback or '0')
end

function p.isIP(frame)
	local ipStr, allowCidr, fallback = getArgs(frame)
	local isValid, corrected = IPUtil.isIP(ipStr, allowCidr)
	return formatResult(isValid, corrected, fallback)
end

function p.isIPv4(frame)
	local ipStr, allowCidr, fallback = getArgs(frame)
	local isValid, corrected = IPUtil.isIPv4(ipStr, allowCidr)
	return formatResult(isValid, corrected, fallback)
end

function p.isIPv6(frame)
	local ipStr, allowCidr, fallback = getArgs(frame)
	local isValid, corrected = IPUtil.isIPv6(ipStr, allowCidr)
	return formatResult(isValid, corrected, fallback)
end

function p.isCIDR(frame)
	local ipStr, _, fallback = getArgs(frame)
	local isValid, corrected = IPUtil.isCIDR(ipStr)
	return formatResult(isValid, corrected, fallback)
end

function p.isIPv4CIDR(frame)
	local ipStr, _, fallback = getArgs(frame)
	local isValid, corrected = IPUtil.isIPv4CIDR(ipStr)
	return formatResult(isValid, corrected, fallback)
end

function p.isIPv6CIDR(frame)
	local ipStr, _, fallback = getArgs(frame)
	local isValid, corrected = IPUtil.isIPv6CIDR(ipStr)
	return formatResult(isValid, corrected, fallback)
end

function p.prettifyIP(frame)
	local ipStr, capitalize, fallback = getArgs(frame)
	local normalized = IPUtil.prettifyIP(ipStr, capitalize)
	return formatResult(not not normalized, normalized, fallback)
end

function p.sanitizeIP(frame)
	local ipStr, capitalize, fallback = getArgs(frame)
	local normalized = IPUtil.sanitizeIP(ipStr, capitalize)
	return formatResult(not not normalized, normalized, fallback)
end

return p