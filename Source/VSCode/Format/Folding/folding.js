function foldingRanges(text) {
    const tokens = [];
    const pairs = new Map();
    const stack = [];
    const commands = [];
    const pattern = /%[^\r\n]*|\\verb\*?([^a-zA-Z\s])[\s\S]*?\1|\\begin\s*\{(verbatim\*?|Verbatim|lstlisting|minted|comment)\}[\s\S]*?\\end\s*\{\2\}|\\(?:[a-zA-Z@]+|[^\r\n])|[{}]|\s+|[^\s{}%\\]+/g;
    let line = 0;
    for (const match of text.matchAll(pattern)) {
        const value = match[0];
        const startLine = line;
        line += (value.match(/\n/g) || []).length;
        if (/^\s/.test(value) || value.startsWith('%')) {
            continue;
        }
        const index = tokens.length;
        tokens.push({ value, line: startLine });
        if (value === '{') {
            stack.push(index);
        } else if (value === '}') {
            const open = stack.pop();
            if (open !== undefined) {
                pairs.set(open, index);
            }
        } else if (value === '\\genPart' || value === '\\genSubPart') {
            commands.push(index);
        }
    }
    const ranges = [];
    for (const command of commands) {
        let next = command + 1;
        const arguments_ = [];
        while (arguments_.length < 4 && tokens[next]?.value === '{' && pairs.has(next)) {
            const end = pairs.get(next);
            arguments_.push(end);
            next = end + 1;
        }
        if (arguments_.length !== 2 && arguments_.length !== 4) {
            continue;
        }
        const start = tokens[command].line;
        const end = tokens[arguments_.at(-1)].line;
        if (end > start) {
            ranges.push({ start, end });
        }
    }
    return ranges;
}

module.exports = { foldingRanges };
