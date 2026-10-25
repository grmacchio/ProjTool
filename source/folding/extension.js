const vscode = require('vscode');
const { foldingRanges } = require('./folding');

function activate(context) {
    const changed = new vscode.EventEmitter();
    const provider = {
        onDidChangeFoldingRanges: changed.event,
        provideFoldingRanges(document) {
            if (!vscode.workspace.getConfiguration('projtool', document.uri).get('folding.enabled')) {
                return [];
            }
            return foldingRanges(document.getText()).map(range =>
                new vscode.FoldingRange(range.start, range.end));
        }
    };
    context.subscriptions.push(
        changed,
        vscode.languages.registerFoldingRangeProvider({ language: 'latex' }, provider),
        vscode.workspace.onDidChangeConfiguration(event => {
            if (event.affectsConfiguration('projtool.folding.enabled')) {
                changed.fire();
            }
        })
    );
}

module.exports = { activate };
