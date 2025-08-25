local p = {}

-- {{tlx}} のスタイル向上版。{{tlx}} の引数にウィキテキストを渡す場合は`<nowiki>`で囲むほかなく、
-- 改行が崩れてしまう。これは`<syntaxhighlight>`を使えば解決するが、このタグをテンプレート引数と
-- 同時に使用し、`<syntaxhighlight>{{{1}}}</syntaxhighlight>`のようにすると、`{{{1}}}`がその
-- まま表示されてしまう。これを防ぐには「タグの内側」の文字列を先に処理したあと、後からその文字列を
-- `<syntaxhighlight>`で囲む必要があり、これはモジュールを使わなければ実装できない。この関数は
-- それを実装する。
--
-- {{#invoke}} の必須引数:
-- `template`: テンプレート名
-- その他: {{template}} の引数
--
-- 例: {{#invoke:Unblock|tlx|template=Unblock|1=...|2=...}}
function p.tlx(frame)
	local args = frame.args
	local template = args.template
	if template == nil or template == '' then
		error('tlx() requires a `template` argument.')
	end

	local params = {}
	table.insert(params, template)
	for k, v in pairs(args) do
		if k ~= 'template' then
			table.insert(params, k .. '=' .. v)
		end
	end

	return frame:extensionTag{
		name = 'syntaxhighlight',
		content = '{{' .. table.concat(params, '\n|') .. '\n}}',
		args = {
			lang = 'wikitext',
			copy = ''
		}
	}
end

-- "利用者（リンク1・リンク2・...）" の複合リンクを作成
-- ※スタイリングに [[Template:Unblock/styles.css]] が必要
function p.userLink(frame)
	local username = frame.args.username
	if username == nil or username == '' then
		error('userLink() requires a `username` argument.')
	end
	local encoded = mw.uri.encode(username, 'WIKI')

	---@param page string
	---@param query table | nil
	---@return string
	local function fullurl(page, query)
		return tostring(mw.uri.fullUrl(page, query))
	end

	--- @type { wikitext: string; classes: string[] | nil; }[]
	--- `wikitext`はウィキテキスト形式のリンク、`classes`はそれを囲む`<span>`に付与するクラス属性
	local toollinkMap = {
		{
			wikitext = string.format('[%s ブロック記録]', fullurl('Special:Log', { type = 'block', page = 'User:' .. encoded }))
		},
		{
			wikitext = string.format('[%s ブロック一覧]', fullurl('Special:BlockList', { wpTarget = encoded }))
		},
		{
			wikitext = string.format('[%s グローバルブロック一覧]', fullurl('Special:GlobalBlockList', { target = encoded }))
		},
		{
			wikitext = string.format('[[Special:Contributions/%s|投稿記録]]', username)
		},
		{
			wikitext = string.format('[[Special:DeletedContributions/%s|削除された投稿記録]]', username),
			classes = { 'sysop-show', 'eliminator-show' }
		},
		{
			wikitext = string.format('[%s 編集フィルター記録]', fullurl('Special:AbuseLog', { wpSearchUser = encoded }))
		},
		{
			wikitext = string.format('[%s アカウント作成記録]', fullurl('Special:Log', { type = 'newusers', user = encoded }))
		},
		{
			wikitext = string.format('[[Special:CheckUserLog/%s|チェック記録]]', username),
			classes = { 'checkuser-show' }
		},
		{
			wikitext = string.format('[[Special:Block/%s|ブロック設定変更]]', username),
			classes = { 'sysop-show' }
		}
	}

	---@param wikitext string
	---@param classes string[] | nil
	---@return string
	local function span(wikitext, classes)
		local node = mw.html.create('span'):wikitext(wikitext)
		if classes then
			for _, class in ipairs(classes) do
				node:addClass(class)
			end
		end
		return tostring(node)
	end

	local toollinks = {}
	for _, obj in ipairs(toollinkMap) do
		table.insert(toollinks, span(obj.wikitext, obj.classes))
	end

	local links = {
		string.format('[[%s|%s]]', '利用者:' .. username, username),
		span(
			-- ツールリンク間の区切り文字は styles.css で疑似要素として組み込み、`table.concat(toollinks, '・')`とはしない
			-- 閲覧者の利用者グループによって非表示になるツールリンクがあるため、文字として組み込んでしまうと「・・」のように
			-- 区切り文字が連続する部分が生じてしまうため
			string.format('（%s）', table.concat(toollinks)),
			{ 'plainlinks', 'template-unblock-usertoollinks' }
		),
		--[[ このコメントアウトを解除すれば、Template本体からは <templatestyles> を除去可
		frame:extensionTag{
			name = 'templatestyles',
			content = '',
			args = { src = 'Unblock/styles.css' }
		}
		]]
	}

	return table.concat(links)
end

return p