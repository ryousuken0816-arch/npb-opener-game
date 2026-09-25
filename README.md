# NPBオーペナゲーム

2008年開始・実在NPB選手（個人用）のペナント/GMシミュレーション（Godot予定）。

## npb_collector/

npb.jp から 2008年以降の選手データを収集する Python スクリプト。

```
pip install requests beautifulsoup4
python collect.py all --start 2008 --end 2026
```

段階: rosters → players → teamstats → awards → drafts → link。
取得HTMLは `cache/`（git管理外）に保存し、再実行時は通信しない。
名前突合の手動補正は `overrides.json`（キー: `年|球団名|成績表上の名前` → 選手ID）。
