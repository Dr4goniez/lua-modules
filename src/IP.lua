-- IP library
-- This library contains classes for working with IP addresses and IP ranges.

-- Load modules
require('strict')
local bit32 = require('bit32')
local libraryUtil = require('libraryUtil')
local checkType = libraryUtil.checkType
local checkTypeMulti = libraryUtil.checkTypeMulti
local makeCheckSelfFunction = libraryUtil.makeCheckSelfFunction

-- Constants
local V4 = 'IPv4'
local V6 = 'IPv6'

--------------------------------------------------------------------------------
-- Helper functions
--------------------------------------------------------------------------------

local function makeValidationFunction(className, isObjectFunc)
	-- Make a function for validating a specific object.
	return function (methodName, argIdx, arg)
		if not isObjectFunc(arg) then
			error(string.format(
				"bad argument #%d to '%s' (not a valid %s object)",
				argIdx, methodName, className
			), 3)
		end
	end
end

--- Remove directional markers and trim surrounding whitespace.
---
--- The following Unicode characters are stripped:
--- - **LRM** (LEFT-TO-RIGHT MARK, U+200E) → `\226\128\142`
--- - **LRE** (LEFT-TO-RIGHT EMBEDDING, U+202A) → `\226\128\170`
--- - **PDF** (POP DIRECTIONAL FORMATTING, U+202C) → `\226\128\172`
---
---@param str string
---@return string
local function clean(str)
	str = str:gsub('\226\128[\142\170\172]', '')
	return str:match('^%s*(.-)%s*$')
end

--------------------------------------------------------------------------------
-- Collection class
-- This is a table used to hold items.
--------------------------------------------------------------------------------

---@class Collection
local Collection = {}
Collection.__index = Collection

function Collection:add(item)
	if item ~= nil then
		self.n = self.n + 1
		self[self.n] = item
	end
end

function Collection:join(sep)
	return table.concat(self, sep)
end

function Collection:remove(pos)
	if self.n > 0 and (pos == nil or (0 < pos and pos <= self.n)) then
		self.n = self.n - 1
		return table.remove(self, pos)
	end
end

function Collection:sort(comp)
	table.sort(self, comp)
end

function Collection:deobjectify()
	-- Turns the collection into a plain array without any special properties
	-- or methods.
	self.n = nil
	setmetatable(self, nil)
end

function Collection.new()
	return setmetatable({n = 0}, Collection)
end

--------------------------------------------------------------------------------
-- RawIP class
-- Numeric representation of an IPv4 or IPv6 address. Used internally.
-- A RawIP object is constructed by adding data to a Collection object and
-- then giving it a new metatable. This is to avoid the memory overhead of
-- copying the data to a new table.
--------------------------------------------------------------------------------

local function parseIPv4(ipStr)
	local octets = Collection.new()
	local s = ipStr .. '.'
	for item in s:gmatch('(.-)%.') do
		octets:add(item)
	end
	if octets.n == 4 then
		for i, s in ipairs(octets) do
			if s:match('^%d+$') then
				local num = tonumber(s)
				if 0 <= num and num <= 255 then
					if num > 0 and s:match('^0') then
						-- A redundant leading zero is for an IP in octal.
						return nil
					end
					octets[i] = num
				else
					return nil
				end
			else
				return nil
			end
		end
		return octets
	end
	return nil
end

local function parseIPv6(ipStr)
	local _, n = ipStr:gsub(':', ':')
	if n < 7 then
		ipStr = ipStr:gsub('::', string.rep(':', 9 - n))
	end
	local hextets = Collection.new()
	for item in (ipStr .. ':'):gmatch('(.-):') do
		hextets:add(item)
	end
	if hextets.n == 8 then
		for i, s in ipairs(hextets) do
			if s == '' then
				hextets[i] = 0
			else
				if s:match('^%x+$') then
					local num = tonumber(s, 16)
					if num and 0 <= num and num <= 65535 then
						hextets[i] = num
					else
						return nil
					end
				else
					return nil
				end
			end
		end
		return hextets
	end
	return nil
end

local RawIP = {}
RawIP.__index = RawIP

-- Constructors
function RawIP.newFromIPv4(ipStr)
	-- Return a RawIP object if ipStr is a valid IPv4 string. Otherwise,
	-- return nil.
	-- This representation is for compatibility with IPv6 addresses.
	ipStr = clean(ipStr)
	local octets = parseIPv4(ipStr)
	if octets then
		local parts = Collection.new()
		for i = 1, 3, 2 do
			parts:add(octets[i] * 256 + octets[i+1])
		end
		return setmetatable(parts, RawIP)
	end
	return nil
end

function RawIP.newFromIPv6(ipStr)
	-- Return a RawIP object if ipStr is a valid IPv6 string. Otherwise,
	-- return nil.
	ipStr = clean(ipStr)
	local parts = parseIPv6(ipStr)
	if parts then
		return setmetatable(parts, RawIP)
	end
	return nil
end

function RawIP.newFromIP(ipStr)
	-- Return a new RawIP object from either an IPv4 string or an IPv6
	-- string. If ipStr is not a valid IPv4 or IPv6 string, then return
	-- nil.
	return RawIP.newFromIPv4(ipStr) or RawIP.newFromIPv6(ipStr)
end

-- Methods
function RawIP:getVersion()
	-- Return a string with the version of the IP protocol we are using.
	return self.n == 2 and V4 or V6
end

function RawIP:isIPv4()
	-- Return true if this is an IPv4 representation, and false otherwise.
	return self.n == 2
end

function RawIP:isIPv6()
	-- Return true if this is an IPv6 representation, and false otherwise.
	return self.n == 8
end

function RawIP:getBitLength()
	-- Return the bit length of the IP address.
	return self.n * 16
end

function RawIP:getAdjacent(previous)
	-- Return a RawIP object for an adjacent IP address. If previous is true
	-- then the previous IP is returned; otherwise the next IP is returned.
	-- Will wraparound:
	--   next      255.255.255.255 → 0.0.0.0
	--             ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff → ::
	--   previous  0.0.0.0 → 255.255.255.255
	--             :: → ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
	local result = Collection.new()
	result.n = self.n
	local carry = previous and 0xffff or 1
	for i = self.n, 1, -1 do
		local sum = self[i] + carry
		if sum >= 0x10000 then
			carry = previous and 0x10000 or 1
			sum = sum - 0x10000
		else
			carry = previous and 0xffff or 0
		end
		result[i] = sum
	end
	return setmetatable(result, RawIP)
end

function RawIP:getPrefix(bitLength)
	-- Return a RawIP object for the prefix of the current IP Address with a
	-- bit length of bitLength.
	local result = Collection.new()
	result.n = self.n
	for i = 1, self.n do
		if bitLength > 0 then
			if bitLength >= 16 then
				result[i] = self[i]
				bitLength = bitLength - 16
			else
				result[i] = bit32.replace(self[i], 0, 0, 16 - bitLength)
				bitLength = 0
			end
		else
			result[i] = 0
		end
	end
	return setmetatable(result, RawIP)
end

function RawIP:getHighestHost(bitLength)
	-- Return a RawIP object for the highest IP with the prefix of length
	-- bitLength. In other words, the network (the most-significant bits)
	-- is the same as the current IP's, but the host bits (the
	-- least-significant bits) are all set to 1.
	local bits = self.n * 16
	local width
	if bitLength <= 0 then
		width = bits
	elseif bitLength >= bits then
		width = 0
	else
		width = bits - bitLength
	end
	local result = Collection.new()
	result.n = self.n
	for i = self.n, 1, -1 do
		if width > 0 then
			if width >= 16 then
				result[i] = 0xffff
				width = width - 16
			else
				result[i] = bit32.replace(self[i], 0xffff, 0, width)
				width = 0
			end
		else
			result[i] = self[i]
		end
	end
	return setmetatable(result, RawIP)
end

function RawIP:_makeIPv6String()
	-- Return an IPv6 string representation of the object. Behavior is
	-- undefined if the current object is IPv4.
	local z1, z2  -- indices of run of zeroes to be displayed as "::"
	local zstart, zcount
	for i = 1, 9 do
		-- Find left-most occurrence of longest run of two or more zeroes.
		if i < 9 and self[i] == 0 then
			if zstart then
				zcount = zcount + 1
			else
				zstart = i
				zcount = 1
			end
		else
			if zcount and zcount > 1 then
				if not z1 or zcount > z2 - z1 + 1 then
					z1 = zstart
					z2 = zstart + zcount - 1
				end
			end
			zstart = nil
			zcount = nil
		end
	end
	local parts = Collection.new()
	for i = 1, 8 do
		if z1 and z1 <= i and i <= z2 then
			if i == z1 then
				if z1 == 1 or z2 == 8 then
					if z1 == 1 and z2 == 8 then
						return '::'
					end
					parts:add(':')
				else
					parts:add('')
				end
			end
		else
			parts:add(string.format('%x', self[i]))
		end
	end
	return parts:join(':')
end

function RawIP:_makeIPv4String()
	-- Return an IPv4 string representation of the object. Behavior is
	-- undefined if the current object is IPv6.
	local parts = Collection.new()
	for i = 1, 2 do
		local w = self[i]
		parts:add(math.floor(w / 256))
		parts:add(w % 256)
	end
	return parts:join('.')
end

function RawIP:__tostring()
	-- Return a string equivalent to given IP address (IPv4 or IPv6).
	if self.n == 2 then
		return self:_makeIPv4String()
	else
		return self:_makeIPv6String()
	end
end

function RawIP:__lt(obj)
	if self.n == obj.n then
		for i = 1, self.n do
			if self[i] ~= obj[i] then
				return self[i] < obj[i]
			end
		end
		return false
	end
	return self.n < obj.n
end

function RawIP:__eq(obj)
	if self.n == obj.n then
		for i = 1, self.n do
			if self[i] ~= obj[i] then
				return false
			end
		end
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- Initialize private methods available to IPAddress and Subnet
--------------------------------------------------------------------------------

-- Both IPAddress and Subnet need access to each others' private constructor
-- functions. IPAddress must be able to make Subnet objects from CIDR strings
-- and from RawIP objects, and Subnet must be able to make IPAddress objects
-- from IP strings and from RawIP objects. These constructors must all be
-- private to ensure correct error levels and to stop other modules from having
-- to worry about RawIP objects. Because they are private, they must be
-- initialized here.
local makeIPAddress, makeIPAddressFromRaw, makeSubnet, makeSubnetFromRaw

-- Objects need to be able to validate other objects that they are passed
-- as input, so initialize those functions here as well.
local validateCollection, validateIPAddress, validateSubnet

--------------------------------------------------------------------------------
-- IPAddress class
-- Represents a single IPv4 or IPv6 address.
--------------------------------------------------------------------------------

local IPAddress = {}

do
	-- dataKey is a unique key to access objects' internal data. This is needed
	-- to access the RawIP objects contained in other IPAddress objects so that
	-- they can be compared with the current object's RawIP object. This data
	-- is not available to other classes or other modules.
	local dataKey = {}

	-- Private static methods
	local function isIPAddressObject(val)
		return type(val) == 'table' and val[dataKey] ~= nil
	end

	validateIPAddress = makeValidationFunction('IPAddress', isIPAddressObject)

	-- Metamethods that don't need upvalues
	local function ipEquals(ip1, ip2)
		return ip1[dataKey].rawIP == ip2[dataKey].rawIP
	end

	local function ipLessThan(ip1, ip2)
		return ip1[dataKey].rawIP < ip2[dataKey].rawIP
	end

	local function concatIP(ip, val)
		return tostring(ip) .. tostring(val)
	end

	local function ipToString(ip)
		return ip:getIP()
	end

	-- Constructors
	makeIPAddressFromRaw = function (rawIP)
		-- Constructs a new IPAddress object from a rawIP object. This function
		-- is for internal use; it is called by IPAddress.new and from other
		-- IPAddress methods, and should be available to the Subnet class, but
		-- should not be available to other modules.
		assert(type(rawIP) == 'table', 'rawIP was type ' .. type(rawIP) .. '; expected type table')

		-- Set up structure
		local obj = {}
		local data = {}
		data.rawIP = rawIP

		-- A function to check whether methods are called with a valid self
		-- parameter.
		local checkSelf = makeCheckSelfFunction(
			'IP',
			'ipAddress',
			obj,
			'IPAddress object'
		)

		-- Public methods
		function obj:getIP()
			checkSelf(self, 'getIP')
			return tostring(data.rawIP)
		end

		function obj:getVersion()
			checkSelf(self, 'getVersion')
			return data.rawIP:getVersion()
		end

		function obj:isIPv4()
			checkSelf(self, 'isIPv4')
			return data.rawIP:isIPv4()
		end

		function obj:isIPv6()
			checkSelf(self, 'isIPv6')
			return data.rawIP:isIPv6()
		end

		function obj:isInCollection(collection)
			checkSelf(self, 'isInCollection')
			validateCollection('isInCollection', 1, collection)
			return collection:containsIP(self)
		end

		function obj:isInSubnet(subnet)
			checkSelf(self, 'isInSubnet')
			local tp = type(subnet)
			if tp == 'string' then
				subnet = makeSubnet(subnet)
			elseif tp == 'table' then
				validateSubnet('isInSubnet', 1, subnet)
			else
				checkTypeMulti('isInSubnet', 1, subnet, {'string', 'table'})
			end
			return subnet:containsIP(self)
		end

		function obj:getSubnet(bitLength)
			checkSelf(self, 'getSubnet')
			checkType('getSubnet', 1, bitLength, 'number')
			if bitLength < 0
				or bitLength > data.rawIP:getBitLength()
				or bitLength ~= math.floor(bitLength)
			then
				error(string.format(
					"bad argument #1 to 'getSubnet' (must be an integer between 0 and %d)",
					data.rawIP:getBitLength()
				), 2)
			end
			return makeSubnetFromRaw(data.rawIP, bitLength)
		end

		function obj:getNextIP()
			checkSelf(self, 'getNextIP')
			return makeIPAddressFromRaw(data.rawIP:getAdjacent())
		end

		function obj:getPreviousIP()
			checkSelf(self, 'getPreviousIP')
			return makeIPAddressFromRaw(data.rawIP:getAdjacent(true))
		end

		-- Metamethods
		return setmetatable(obj, {
			__eq = ipEquals,
			__lt = ipLessThan,
			__concat = concatIP,
			__tostring = ipToString,
			__index = function (self, key)
				-- If any code knows the unique data key, allow it to access
				-- the data table.
				if key == dataKey then
					return data
				end
			end,
			__metatable = false, -- don't allow access to the metatable
		})
	end

	makeIPAddress = function (ip)
		local rawIP = RawIP.newFromIP(ip)
		if not rawIP then
			error(string.format("'%s' is an invalid IP address", ip), 3)
		end
		return makeIPAddressFromRaw(rawIP)
	end

	function IPAddress.new(ip)
		checkType('IPAddress.new', 1, ip, 'string')
		return makeIPAddress(ip)
	end
end

--------------------------------------------------------------------------------
-- Subnet class
-- Represents a block of IPv4 or IPv6 addresses.
--------------------------------------------------------------------------------

local Subnet = {}

do
	-- uniqueKey is a unique, private key used to test whether a given object
	-- is a Subnet object.
	local uniqueKey = {}

	-- Metatable
	local mt = {
		__index = function (self, key)
			if key == uniqueKey then
				return true
			end
		end,
		__eq = function (self, obj)
			return self:getCIDR() == obj:getCIDR()
		end,
		__concat = function (self, obj)
			return tostring(self) .. tostring(obj)
		end,
		__tostring = function (self)
			return self:getCIDR()
		end,
		__metatable = false
	}

	-- Private static methods
	local function isSubnetObject(val)
		-- Return true if val is a Subnet object, and false otherwise.
		return type(val) == 'table' and val[uniqueKey] ~= nil
	end

	-- Function to validate subnet objects.
	-- Params:
	-- methodName (string) - the name of the method being validated
	-- argIdx (number) - the position of the argument in the argument list
	-- arg - the argument to be validated
	validateSubnet = makeValidationFunction('Subnet', isSubnetObject)

	-- Constructors
	makeSubnetFromRaw = function (rawIP, bitLength)
		-- Set up structure
		local obj = setmetatable({}, mt)
		local data = {
			rawIP = rawIP,
			bitLength = bitLength,
		}

		-- A function to check whether methods are called with a valid self
		-- parameter.
		local checkSelf = makeCheckSelfFunction(
			'IP',
			'subnet',
			obj,
			'Subnet object'
		)

		-- Public methods
		function obj:getPrefix()
			checkSelf(self, 'getPrefix')
			if not data.prefix then
				data.prefix = makeIPAddressFromRaw(
					data.rawIP:getPrefix(data.bitLength)
				)
			end
			return data.prefix
		end

		function obj:getHighestIP()
			checkSelf(self, 'getHighestIP')
			if not data.highestIP then
				data.highestIP = makeIPAddressFromRaw(
					data.rawIP:getHighestHost(data.bitLength)
				)
			end
			return data.highestIP
		end

		function obj:getBitLength()
			checkSelf(self, 'getBitLength')
			return data.bitLength
		end

		function obj:getCIDR()
			checkSelf(self, 'getCIDR')
			return string.format(
				'%s/%d',
				tostring(self:getPrefix()), self:getBitLength()
			)
		end

		function obj:getVersion()
			checkSelf(self, 'getVersion')
			return data.rawIP:getVersion()
		end

		function obj:isIPv4()
			checkSelf(self, 'isIPv4')
			return data.rawIP:isIPv4()
		end

		function obj:isIPv6()
			checkSelf(self, 'isIPv6')
			return data.rawIP:isIPv6()
		end

		function obj:containsIP(ip)
			checkSelf(self, 'containsIP')
			local tp = type(ip)
			if tp == 'string' then
				ip = makeIPAddress(ip)
			elseif tp == 'table' then
				validateIPAddress('containsIP', 1, ip)
			else
				checkTypeMulti('containsIP', 1, ip, {'string', 'table'})
			end
			if self:getVersion() == ip:getVersion() then
				return self:getPrefix() <= ip and ip <= self:getHighestIP()
			end
			return false
		end

		function obj:overlapsCollection(collection)
			checkSelf(self, 'overlapsCollection')
			validateCollection('overlapsCollection', 1, collection)
			return collection:overlapsSubnet(self)
		end

		function obj:overlapsSubnet(subnet)
			checkSelf(self, 'overlapsSubnet')
			local tp = type(subnet)
			if tp == 'string' then
				subnet = makeSubnet(subnet)
			elseif tp == 'table' then
				validateSubnet('overlapsSubnet', 1, subnet)
			else
				checkTypeMulti('overlapsSubnet', 1, subnet, {'string', 'table'})
			end
			if self:getVersion() == subnet:getVersion() then
				return (
					subnet:getHighestIP() >= self:getPrefix() and
					subnet:getPrefix() <= self:getHighestIP()
				)
			end
			return false
		end

		function obj:walk()
			checkSelf(self, 'walk')
			local started
			local current = self:getPrefix()
			local highest = self:getHighestIP()
			return function ()
				if not started then
					started = true
					return current
				end
				if current < highest then
					current = current:getNextIP()
					return current
				end
			end
		end

		return obj
	end

	makeSubnet = function (cidr)
		-- Return a Subnet object from a CIDR string. If the CIDR string is
		-- invalid, throw an error.
		cidr = clean(cidr)
		local lhs, rhs = cidr:match('^(.-)/(%d+)$')
		if lhs then
			local bits = lhs:find(':', 1, true) and 128 or 32
			local n = tonumber(rhs)
			if n and n <= bits and (n == 0 or not rhs:find('^0')) then
				-- The right-hand side is a number between 0 and 32 (for IPv4)
				-- or 0 and 128 (for IPv6) and doesn't have any leading zeroes.
				local base = RawIP.newFromIP(lhs)
				if base then
					-- The left-hand side is a valid IP address.
					local prefix = base:getPrefix(n)
					if base == prefix then
						-- The left-hand side is the lowest IP in the subnet.
						return makeSubnetFromRaw(prefix, n)
					end
				end
			end
		end
		error(string.format("'%s' is an invalid CIDR string", cidr), 3)
	end

	function Subnet.new(cidr)
		checkType('Subnet.new', 1, cidr, 'string')
		return makeSubnet(cidr)
	end
end

--------------------------------------------------------------------------------
-- Ranges class
-- Holds a list of IPAdress pairs representing contiguous IP ranges.
--------------------------------------------------------------------------------

local Ranges = Collection.new()
Ranges.__index = Ranges

function Ranges.new()
	return setmetatable({}, Ranges)
end

function Ranges:add(ip1, ip2)
	validateIPAddress('add', 1, ip1)
	if ip2 ~= nil then
		validateIPAddress('add', 2, ip2)
		if ip1 > ip2 then
			error('The first IP must be less than or equal to the second', 2)
		end
	end
	Collection.add(self, {ip1, ip2 or ip1})
end

function Ranges:merge()
	self:sort(
		function (lhs, rhs)
			-- Sort by second value, then first.
			if lhs[2] == rhs[2] then
				return lhs[1] < rhs[1]
			end
			return lhs[2] < rhs[2]
		end
	)
	local pos = self.n
	while pos > 1 do
		for i = pos - 1, 1, -1 do
			local ip1 = self[i][2]
			local ip2 = ip1:getNextIP()
			if ip2 < ip1 then
				ip2 = ip1  -- don't wrap around
			end
			if self[pos][1] > ip2 then
				break
			end
			ip1 = self[i][1]
			ip2 = self[pos][1]
			self[i] = {ip1 > ip2 and ip2 or ip1, self[pos][2]}
			self:remove(pos)
			pos = pos - 1
			if pos <= 1 then
				break
			end
		end
		pos = pos - 1
	end
end

--------------------------------------------------------------------------------
-- IPCollection class
-- Holds a list of IP addresses/subnets. Used internally.
-- Each address/subnet has the same version (either IPv4 or IPv6).
--------------------------------------------------------------------------------

local IPCollection = {}
IPCollection.__index = IPCollection

function IPCollection.new(version)
	assert(
		version == V4 or version == V6,
		'IPCollection.new called with an invalid version'
	)
	local obj = {
		version = version,               -- V4 or V6
		addresses = Collection.new(),    -- valid IP addresses
		subnets = Collection.new(),      -- valid subnets
		omitted = Collection.new(),      -- not-quite valid strings
	}
	return obj
end

function IPCollection:getVersion()
	-- Return a string with the IP version of addresses in this collection.
	return self.version
end

function IPCollection:_store(hit, stripColons)
	local maker, location
	if hit:find('/', 1, true) then
		maker = Subnet.new
		location = self.subnets
	else
		maker = IPAddress.new
		location = self.addresses
	end
	local success, obj = pcall(maker, hit)
	if success then
		location:add(obj)
	else
		if stripColons then
			local colons, hit = hit:match('^(:*)(.*)')
			if colons ~= '' then
				self:_store(hit)
				return
			end
		end
		self.omitted:add(hit)
	end
end

function IPCollection:_assertVersion(version, msg)
	if self.version ~= version then
		error(msg, 3)
	end
end

function IPCollection:addIP(ip)
	local tp = type(ip)
	if tp == 'string' then
		ip = makeIPAddress(ip)
	elseif tp == 'table' then
		validateIPAddress('addIP', 1, ip)
	else
		checkTypeMulti('addIP', 1, ip, {'string', 'table'})
	end
	self:_assertVersion(ip:getVersion(), 'addIP called with incorrect IP version')
	self.addresses:add(ip)
	return self
end

function IPCollection:addSubnet(subnet)
	local tp = type(subnet)
	if tp == 'string' then
		subnet = makeSubnet(subnet)
	elseif tp == 'table' then
		validateSubnet('addSubnet', 1, subnet)
	else
		checkTypeMulti('addSubnet', 1, subnet, {'string', 'table'})
	end
	self:_assertVersion(subnet:getVersion(), 'addSubnet called with incorrect subnet version')
	self.subnets:add(subnet)
	return self
end

function IPCollection:containsIP(ip)
	-- Return true, obj if ip is in this collection,
	-- where obj is the first IPAddress or Subnet with the ip.
	-- Otherwise, return false.
	local tp = type(ip)
	if tp == 'string' then
		ip = makeIPAddress(ip)
	elseif tp == 'table' then
		validateIPAddress('containsIP', 1, ip)
	else
		checkTypeMulti('containsIP', 1, ip, {'string', 'table'})
	end
	if self:getVersion() == ip:getVersion() then
		for _, item in ipairs(self.addresses) do
			if item == ip then
				return true, item
			end
		end
		for _, item in ipairs(self.subnets) do
			if item:containsIP(ip) then
				return true, item
			end
		end
	end
	return false
end

function IPCollection:getRanges()
	-- Return a sorted table of IP pairs equivalent to the collection.
	-- Each IP pair is a table representing a contiguous range of
	-- IP addresses from pair[1] to pair[2] inclusive (IPAddress objects).
	local ranges = Ranges.new()
	for _, item in ipairs(self.addresses) do
		ranges:add(item)
	end
	for _, item in ipairs(self.subnets) do
		ranges:add(item:getPrefix(), item:getHighestIP())
	end
	ranges:merge()
	ranges:deobjectify()
	return ranges
end

function IPCollection:overlapsSubnet(subnet)
	-- Return true, obj if subnet overlaps this collection,
	-- where obj is the first IPAddress or Subnet overlapping the subnet.
	-- Otherwise, return false.
	local tp = type(subnet)
	if tp == 'string' then
		subnet = makeSubnet(subnet)
	elseif tp == 'table' then
		validateSubnet('overlapsSubnet', 1, subnet)
	else
		checkTypeMulti('overlapsSubnet', 1, subnet, {'string', 'table'})
	end
	if self:getVersion() == subnet:getVersion() then
		for _, item in ipairs(self.addresses) do
			if subnet:containsIP(item) then
				return true, item
			end
		end
		for _, item in ipairs(self.subnets) do
			if subnet:overlapsSubnet(item) then
				return true, item
			end
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- IPv4Collection class
-- Holds a list of IPv4 addresses/subnets.
--------------------------------------------------------------------------------

local IPv4Collection = setmetatable({}, IPCollection)
IPv4Collection.__index = IPv4Collection

function IPv4Collection.new()
	return setmetatable(IPCollection.new(V4), IPv4Collection)
end

function IPv4Collection:addFromString(text)
	-- Extract any IPv4 addresses or CIDR subnets from given text.
	checkType('addFromString', 1, text, 'string')
	text = text:gsub('[:!"#&\'()+,%-;<=>?[%]_{|}]', ' ')
	for hit in text:gmatch('%S+') do
		if hit:match('^%d+%.%d+[%.%d/]+$') then
			local _, n = hit:gsub('%.', '.')
			if n >= 3 then
				self:_store(hit)
			end
		end
	end
	return self
end

--------------------------------------------------------------------------------
-- IPv6Collection class
-- Holds a list of IPv6 addresses/subnets.
--------------------------------------------------------------------------------

local IPv6Collection = setmetatable({}, IPCollection)
IPv6Collection.__index = IPv6Collection

do
	-- Private static methods
	local function isCollectionObject(val)
		-- Return true if val is probably derived from an IPCollection object,
		-- otherwise return false.
		if type(val) == 'table' then
			local mt = getmetatable(val)
			if mt == IPv4Collection or mt == IPv6Collection then
				return true
			end
		end
		return false
	end

	validateCollection = makeValidationFunction('IPCollection', isCollectionObject)

	function IPv6Collection.new()
		return setmetatable(IPCollection.new(V6), IPv6Collection)
	end

	function IPv6Collection:addFromString(text)
		-- Extract any IPv6 addresses or CIDR subnets from given text.
		-- Want to accept all valid IPv6 despite the fact that addresses used
		-- are unlikely to start with ':'.
		-- Also want to be able to parse arbitrary wikitext which might use
		-- colons for indenting.
		-- Therefore, if an address at the start of a line is valid, use it;
		-- otherwise strip any leading colons and try again.
		checkType('addFromString', 1, text, 'string')
		for line in string.gmatch(text .. '\n', '[\t ]*(.-)[\t\r ]*\n') do
			line = line:gsub('[!"#&\'()+,%-;<=>?[%]_{|}]', ' ')
			for position, hit in line:gmatch('()(%S+)') do
				local ip = hit:match('^([:%x]+)/?%d*$')
				if ip then
					local _, n = ip:gsub(':', ':')
					if n >= 2 then
						self:_store(hit, position == 1)
					end
				end
			end
		end
		return self
	end
end

--------------------------------------------------------------------------------
-- Util class (static)
-- Holds utility functions.
--------------------------------------------------------------------------------

---@param parts Collection
---@param sanitize boolean?
---@return string
local function formatIP(parts, sanitize)
	if parts.n == 4 then
		return parts:join('.')
	elseif parts.n == 8 then
		if sanitize then
			local hextets = Collection.new()
			for _, num in ipairs(parts) do
				hextets:add(string.format('%x', num))
			end
			return hextets:join(':')
		end
		return RawIP._makeIPv6String(parts)
	else
		error('Invalid length for "parts": ' .. parts.n)
	end
end

--- Verifies whether a string is a valid IP or CIDR.
---
--- @param str string The input string (IP or CIDR).
--- @param allowCidr boolean | 'require'
--- - `false`: reject CIDR notation (only plain IP allowed).
--- - `true`: allow both plain IP and CIDR.
--- - `'require'`: only CIDR notation allowed.
--- @param version (4 | 6)? Force IPv4 or IPv6 validation. If omitted, both are attempted.
--- @param forceCorrection (boolean | 'sanitize')? If truthy, always return a corrected string:
--- - `true`: return compressed/canonical form.
--- - `'sanitize'`: return verbose, normalized form.
--- @return boolean, string?
--- Returns `true` if valid, `false` if not. Second return value is the "corrected" CIDR
--- (normalized form), if the input CIDR did not represent the exact network address.
local function verifyIP(str, allowCidr, version, forceCorrection)
	str = clean(str)

	-- Try to split into IP part and mask length if CIDR notation is present
	---@type string|nil, string|nil
	local ipStr, bitLen = str:match('^(.*)/(%d+)$')

	if (not allowCidr and bitLen) or (allowCidr == 'require' and not bitLen) then
		return false
	end
	ipStr = ipStr or str -- Fallback: if no CIDR mask is present, ipStr = str

	-- Parse into numeric parts depending on requested version
	local parts
	if version == 4 then
		parts = parseIPv4(ipStr)
	elseif version == 6 then
		parts = parseIPv6(ipStr)
	else
		parts = parseIPv4(ipStr) or parseIPv6(ipStr)
	end
	if not parts then
		-- Parsing failed: Invalid IP
		return false
	elseif not allowCidr or not bitLen then
		-- Valid plain IP (no CIDR expected or allowed)
		local corrected
		if forceCorrection then
			corrected = formatIP(parts, forceCorrection == 'sanitize')
		end
		return true, corrected
	end

	-- At this point: CIDR is allowed and `bitLen` is defined

	-- Validate CIDR mask length
	local bits = tonumber(bitLen)
	local isV4 = parts.n == 4
	if (isV4 and not (0 <= bits and bits <= 32))
		or (not isV4 and not (0 <= bits and bits <= 128))
	then
		return false
	end

	-- Build the netmask from the CIDR length
	local partBits = isV4 and 8 or 16 -- Bits per part (octet or hextet)
	local partMax = isV4 and 0xff or 0xffff
	local netmaskParts = {}
	for i = 1, parts.n do
		local bitsRemaining = bits - (i - 1) * partBits
		if bitsRemaining >= partBits then
			-- Fully covered segment: all 1s
			netmaskParts[i] = partMax
		elseif bitsRemaining > 0 then
			-- Partially covered segment: some 1s followed by 0s
			netmaskParts[i] = bit32.band(
				bit32.lshift(partMax, partBits - bitsRemaining),
				partMax
			)
		else
			-- Mask does not cover this segment: all 0s
			netmaskParts[i] = 0
		end
	end

	-- Calculate the canonical network address
	local networkAddressParts = Collection.new()
	local validNetworkAddress = true
	for i, num in ipairs(parts) do
		-- Apply mask to each segment
		local part = bit32.band(num, netmaskParts[i])
		networkAddressParts:add(part)
		if part ~= num then
			validNetworkAddress = false
		end
	end

	-- Suggest correction if the input wasn't already the canonical network address
	local corrected
	if not validNetworkAddress or forceCorrection then
		corrected = string.format(
			'%s/%d',
			formatIP(networkAddressParts, forceCorrection == 'sanitize'),
			bits
		)
	end

	return true, corrected
end

local Util = {}

---@param str string
---@return string
function Util.clean(str)
	return clean(str)
end

---@param str string
---@param allowCidr boolean?
---@return boolean isValid `true` if valid, `false` otherwise.
---@return string? corrected If CIDR and not canonical, the corrected canonical form.
function Util.isIP(str, allowCidr)
	return verifyIP(str, not not allowCidr)
end

---@param str string
---@param allowCidr boolean?
---@return boolean isValid
---@return string? corrected
function Util.isIPv4(str, allowCidr)
	return verifyIP(str, not not allowCidr, 4)
end

---@param str string
---@param allowCidr boolean?
---@return boolean isValid
---@return string? corrected
function Util.isIPv6(str, allowCidr)
	return verifyIP(str, not not allowCidr, 6)
end

---@param str string
---@return boolean isValid
---@return string? corrected
function Util.isCIDR(str)
	return verifyIP(str, 'require')
end

---@param str string
---@return boolean isValid
---@return string? corrected
function Util.isIPv4CIDR(str)
	return verifyIP(str, 'require', 4)
end

---@param str string
---@return boolean isValid
---@return string? corrected
function Util.isIPv6CIDR(str)
	return verifyIP(str, 'require', 6)
end

--- Internal helper to normalize and optionally capitalize or sanitize an IP.
---
---@param str string Input string (IP or CIDR).
---@param capitalize boolean? If true, return uppercase representation.
---@param sanitize boolean? If true, return fully expanded "sanitized" form.
---@return string? normalized Canonical form of the IP/CIDR, or `nil` if invalid.
function Util._formatIP(str, capitalize, sanitize)
	local isIP, normalized = verifyIP(str, true, nil, sanitize and 'sanitize' or true)
	if not isIP then
		return nil
	end
	if not normalized then
		error('Internal error: "normalized" is nil')
	end
	if capitalize then
		normalized = normalized:upper()
	end
	return normalized
end

--- Normalize an IP or CIDR into its canonical "prettified" form.
--- - IPv6 will use `::` zero-compression (shortest form).
--- - IPv4 will use dotted-decimal notation.
---
---@param str string Input string (IP or CIDR).
---@param capitalize boolean? If true, return uppercase IPv6 letters (A–F).
---@return string? prettified Prettified form, or `nil` if invalid.
function Util.prettifyIP(str, capitalize)
	return Util._formatIP(str, capitalize)
end

--- Normalize an IP or CIDR into its verbose, "sanitized" form.
--- - IPv6 will expand all hextets (no `::` compression).
--- - IPv4 will remain dotted-decimal.
---
---@param str string Input string (IP or CIDR).
---@param capitalize boolean? If true, return uppercase IPv6 letters (A–F).
---@return string? sanitized Sanitized form, or `nil` if invalid.
function Util.sanitizeIP(str, capitalize)
	return Util._formatIP(str, capitalize, true)
end

return {
	IPAddress = IPAddress,
	Subnet = Subnet,
	IPv4Collection = IPv4Collection,
	IPv6Collection = IPv6Collection,
	Util = Util
}