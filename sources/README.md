本目录是 **上游源码的本地 checkout**，不入库。

接入清单在 `../repos/*.json`。增删仓库只改那份清单，然后：

```bash
./scripts/repo.sh sync <id>    # clone / fetch
./scripts/repo.sh build <id>   # 编到 <path>/<bin>
```

`sources/*` 已 gitignore。每个子目录是独立 git 仓，方便改源码、开分支、提上游 PR。
