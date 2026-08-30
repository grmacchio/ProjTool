local function append(collection, value)
    collection[#collection + 1] = value
end

local function html_escape(value)
    return value:gsub("&", "&amp;"):gsub('"', "&quot;")
        :gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function inlines_html(inlines)
    local html = {}
    for _, inline in ipairs(inlines) do
        if inline.t == "Str" then
            append(html, html_escape(inline.text))
        elseif inline.t == "Space" or inline.t == "SoftBreak" then
            append(html, " ")
        elseif inline.t == "LineBreak" then
            append(html, "<br>")
        elseif inline.t == "Strong" then
            append(html, "<strong>" .. inlines_html(inline.content) ..
                "</strong>")
        elseif inline.t == "Emph" then
            append(html, "<em>" .. inlines_html(inline.content) .. "</em>")
        elseif inline.t == "Code" then
            append(html, "<code>" .. html_escape(inline.text) .. "</code>")
        elseif inline.t == "Link" then
            local target = html_escape(inline.target)
            append(html, '<a href="' .. target .. '">' .. target .. "</a>")
        elseif inline.t == "Span" then
            append(html, inlines_html(inline.content))
        else
            append(html, html_escape(pandoc.utils.stringify(inline)))
        end
    end
    return table.concat(html)
end

local function field_parts(field)
    local content = field.t == "Span" and field.content or {field}
    if content[1] and content[1].t == "Strong" then
        local value = {}
        for index = 2, #content do
            if not (index == 2 and content[index].t == "Space") then
                append(value, content[index])
            end
        end
        return inlines_html({content[1]}), inlines_html(value)
    end
    return nil, inlines_html(content)
end

function Div(div)
    if div.identifier ~= "refs" then
        return nil
    end

    local output = {}
    for _, entry in ipairs(div.content) do
        local paragraph = entry.content[1]
        local left = paragraph and paragraph.content[1]
        local right = paragraph and paragraph.content[2]
        if not left or left.t ~= "Span" or
            not right or right.t ~= "Span" then
            error("unsupported bibliography entry structure", 0)
        end

        local number = inlines_html(left.content):gsub("%s+$", "")
        local html = {
            '<div id="' .. entry.identifier .. '" style="margin:0 0 1em 0">',
            '<table role="presentation" width="100%" border="3" rules="all" ' ..
                'frame="box" cellpadding="6" cellspacing="0" ' ..
                'style="border:3px solid currentColor;border-collapse:collapse">',
            "<tbody>"
        }
        for index, field in ipairs(right.content) do
            local label, value = field_parts(field)
            append(html, "<tr>")
            if index == 1 then
                append(html, '<td width="48" align="center" valign="middle" ' ..
                    'style="border:1px solid currentColor" ' ..
                    'rowspan="' .. #right.content .. '">' .. number .. "</td>")
            end
            append(html, '<td width="96" align="left" valign="top" nowrap ' ..
                'style="border:1px solid currentColor">' ..
                (label or "<strong>Location:</strong>") .. "</td>")
            append(html, '<td width="100%" align="left" valign="top" ' ..
                'style="border:1px solid currentColor">' .. value .. "</td>")
            append(html, "</tr>")
        end
        append(html, "</tbody>")
        append(html, "</table>")
        append(html, "</div>")
        append(output, pandoc.RawBlock("html", table.concat(html, "\n")))
    end
    return output
end
