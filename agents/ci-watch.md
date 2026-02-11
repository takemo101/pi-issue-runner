PRを作成し、CIの結果を確認します。**マージは行いません。**

#### 1. プッシュ
```bash
git push -u origin feature/{{branch_name}}
```

#### 2. PR作成
> bodyに必ず `Closes #{{issue_number}}` を含めてください。

```bash
gh pr create \
  --title "<type>: {{issue_title}}" \
  --body "## Summary
Closes #{{issue_number}}

## Changes
- <変更内容を記載>

## Testing
- <テスト内容を記載>"
```

#### 3. CI監視
```bash
gh pr checks <PR_NUMBER> --watch --fail-fast
```

**CI失敗時の対応**（最大3回まで再試行）:
1. `gh run view --log-failed` で失敗ログを取得
2. 失敗タイプを判定（format / lint / test / build）
3. 修正を実施:
   - format/lint → 自動修正ツールを実行
   - test/build → ログを分析してコードを修正
4. コミット・プッシュしてCIを再実行
5. 3回失敗したら PRを draft 化してエラーを報告

`./scripts/ci-fix-helper.sh` が利用可能な場合はそれを活用してください。

#### 4. 知見の永続化（オプション）
タスク全体を通じて重要な発見があった場合のみ：
1. `docs/decisions/NNN-問題名.md` にADRを作成（連番は既存ファイルに続ける）
2. `AGENTS.md` の「既知の制約」に1行サマリーとリンクを追加

> 軽微な修正（typo、設定変更等）では不要です。

#### 完了条件
- [ ] コードがリモートにプッシュされた
- [ ] PRが作成された（`Closes #{{issue_number}}` を含む）
- [ ] CIがパスした
- [ ] PRはマージ**しない**（人間がレビュー後にマージする）
