---Check whether an array includes a certain value.
---@param array table
---@param value any
---@return boolean
local function includes(array, value)
	for _, v in ipairs(array) do
		if v == value then
			return true
		end
	end
	return false
end

local p = {}

---Format the current namespace number into a readable namespace name in Japanese. 
---@param targetNamespaces table|nil Optional array of namespace numbers.
---If provided, only convert the page type if the array includes the current namespace;
---otherwise, returns 'ページ', or 'ノート' in the case of a talk page.
---@return string
function p._main(targetNamespaces)
	local ns = mw.title.getCurrentTitle().namespace
	if ns % 2 == 1 then
		return 'ノート'
	end
	local map = {
		[0] = '記事',
		[2] = '利用者ページ',
		[4] = 'プロジェクトページ',
		[6] = 'ファイル',
		[8] = 'インターフェースページ',
		[10] = 'テンプレート',
		[12] = 'ヘルプページ',
		[14] = 'カテゴリ',
		[100] = 'ポータル',
		[102] = 'プロジェクト',
		[828] = 'モジュール'
	}
	if map[ns] and (not targetNamespaces or includes(targetNamespaces, ns)) then
		return map[ns]
	else
		return 'ページ'
	end
end

function p.auto(_frame)
	return p._main()
end

function p.byIds(frame)
	local targetNamespaces = {}
	for _, v in pairs(frame.args) do
		local num = tonumber(v)
		if num then
			table.insert(targetNamespaces, num)
		end
	end
	return p._main(targetNamespaces)
end

return p