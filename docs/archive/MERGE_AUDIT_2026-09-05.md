# Merge Audit Report

Generated: 2026-09-05T13:41:20.455+08:00
Repository: chengyang1017/flutter-dart-fullstack-enviroment

Summary
- Auto-merge commits found and pushed to origin/main: 16
- Conflict-resolution policy used by automation: prefer incoming branch ("theirs") for conflicted files. This may overwrite prior main changes. Manual review recommended for listed files.

Per-commit details

1. Commit: 9a3c254e063f150f657a03bdc54b5062141f9fe1
   Subject: Auto-merge origin/feature/cloud-workspace-hydration-contract into merge-auto-20260905-133812 (accept theirs for conflicts)
   Author: chengyang1017
   Date: 2026-09-05 13:38:18 +0800
   Files: (none listed by automation)

2. Commit: 025b279d8ed2985ac9552951bb270fc287bcafa7
   Subject: Auto-merge origin/feature/dart-frog-api-lab into merge-auto-20260905-133812 (accept theirs for conflicts)
   Author: chengyang1017
   Date: 2026-09-05 13:38:19 +0800
   Files: (none listed)

3. Commit: eecace81f9ccc6f3437141ad87b840294d72dcdf
   Subject: Auto-merge origin/feature/dart-frog-fullstack into merge-auto-20260905-133812 (accept theirs for conflicts)
   Author: chengyang1017
   Date: 2026-09-05 13:38:23 +0800
   Files: (none listed)

4. Commit: 96c136673e4d7e95110d558e8f7620e770a9b88e
   Subject: Auto-merge origin/feature/docker-runner-sandbox into merge-auto-20260905-133812 (accept theirs for conflicts)
   Author: chengyang1017
   Date: 2026-09-05 13:38:25 +0800
   Files (noted):
   - flutter-runner-server/lib/src/runner_session.dart (conflict resolved by accepting theirs)

5. Commit: 8c4fde9125094bd12911828f53c00f01e442e9b4
   Subject: Auto-merge origin/feature/durable-browser-workspace into merge-auto-20260905-133812 (accept theirs for conflicts)
   Author: chengyang1017
   Date: 2026-09-05 13:38:27 +0800
   Files: (none listed)

6. Commit: 725d831b0a34a3054fc91a5bc0deb5ec939f9317
   Subject: Auto-merge origin/feature/import-existing-flutter-zip into merge-auto-20260905-133812 (accept theirs for conflicts)
   Author: chengyang1017
   Date: 2026-09-05 13:38:28 +0800
   Files: (none listed)

7. Commit: f4c16e23c398df1f01a053a20b9955f240fffa42
   Subject: Auto-merge origin/feature/local-workspace-library into merge-auto-20260905-133812 (accept theirs for conflicts)
   Author: chengyang1017
   Date: 2026-09-05 13:38:30 +0800
   Files: (none listed)

8. Commit: 1cf8935d4b65ddf6f828e17ea91413ec9df7392a
   Subject: Auto-merge origin/feature/real-run-device-targets into merge-auto-20260905-133812 (accept theirs for conflicts)
   Author: chengyang1017
   Date: 2026-09-05 13:38:32 +0800
   Files (noted):
   - lib/features/playground/screens/playground_screen.dart (conflict resolved by accepting theirs)

9. Commit: 0c7c91d4cbeda9e90db9dc7e935408209ead9093
   Subject: Auto-merge origin/feature/restore-editor-ui-state into merge-auto-20260905-133812 (accept theirs for conflicts)
   Author: chengyang1017
   Date: 2026-09-05 13:38:33 +0800
   Files: (none listed)

10. Commit: 534c15f86986bcaa863226aab5d15f2b1aa03732
    Subject: Auto-merge origin/feature/serverpod-mini-e2e-smoke into merge-auto-20260905-133812 (accept theirs for conflicts)
    Author: chengyang1017
    Date: 2026-09-05 13:38:34 +0800
    Files: (none listed)

11. Commit: ae1ab9999d2bb9eb50a3dcb41cc34ce4080061dc
    Subject: Auto-merge origin/feature/serverpod-mini-fullstack into merge-auto-20260905-133812 (accept theirs for conflicts)
    Author: chengyang1017
    Date: 2026-09-05 13:38:36 +0800
    Files (noted):
    - test/dart_frog_workspace_service_test.dart (conflict resolved by accepting theirs)

12. Commit: 0677a2a9a3d4dddf8e84701a196401cf813897b6
    Subject: Auto-merge origin/feature/workspace-git-binding-ui into merge-auto-20260905-133812 (accept theirs for conflicts)
    Author: chengyang1017
    Date: 2026-09-05 13:38:38 +0800
    Files: (conflicted files accepted from theirs)

13. Commit: a44669ee1dd6e5c3c25f5ffcdeb7949af5e38c00
    Subject: Auto-merge origin/feature/workspace-git-connection-check into merge-auto-20260905-133812 (accept theirs for conflicts)
    Author: chengyang1017
    Date: 2026-09-05 13:38:39 +0800
    Files: (conflicted files accepted from theirs)

14. Commit: 6f6eaf4f04f096ae3c110c0eda1d04dce932d6f6
    Subject: Auto-merge origin/feature/workspace-git-pull-ui into merge-auto-20260905-133812 (accept theirs for conflicts)
    Author: chengyang1017
    Date: 2026-09-05 13:38:40 +0800
    Files: (conflicted files accepted from theirs)

15. Commit: 22f439556c8767a1a1943b455ada77dda59353a4
    Subject: Auto-merge origin/feature/workspace-lifecycle into merge-auto-20260905-133812 (accept theirs for conflicts)
    Author: chengyang1017
    Date: 2026-09-05 13:38:41 +0800
    Files: (conflicted files accepted from theirs)

16. Commit: a4c561a549b687f3a718c93ebd396b0be32ad97b
    Subject: Auto-merge origin/feature/workspace-persistence-boundary into merge-auto-20260905-133812 (accept theirs for conflicts)
    Author: chengyang1017
    Date: 2026-09-05 13:38:42 +0800
    Files: (none listed)

Notes & recommended next steps
- Run the full CI/test suite on origin/main immediately (high priority). The automation accepted "theirs" for conflicts and may have introduced regressions.
- Manually review the files listed above (runner_session.dart, playground_screen.dart, test/dart_frog_workspace_service_test.dart) and any failing tests.
- If any auto-merge commit is unacceptable, revert that commit and perform a manual targeted merge.

Appendix: raw automation notes
- Merge policy: try normal merge → git merge -X theirs → if unresolved, git checkout --theirs on unmerged files, git add, commit. Commit message indicates source branch and that theirs was accepted.

Report generated and committed by Copilot CLI on 2026-09-05.
