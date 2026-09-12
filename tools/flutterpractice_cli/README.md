# flutterpractice CLI

`flutterpractice` rebuilds a brand-new local Flutter project from a portable
`.flutterpractice` package exported by the browser workspace.

The package stores portable workspace source/configuration files. Flutter
platform scaffolding and runtime-generated directories are recreated locally by
`flutter create`; they are not carried inside the practice package.

## Create a new project

```powershell
flutterpractice create practice.flutterpractice --output C:\Projects\practice_copy
```

Current development invocation from this repository:

```powershell
cd tool\flutterpractice_cli
dart run bin\flutterpractice.dart create ..\..\practice.flutterpractice --output C:\Projects\practice_copy
```

The target directory **must not already exist**. There is intentionally no
`--force` overwrite mode.

Creation flow:

1. validate the practice package and portable paths;
2. run `flutter create --no-pub` for a fresh local scaffold;
3. remove the generated `lib/`, `test/`, `pubspec.yaml`, and
   `analysis_options.yaml` user area;
4. restore the portable workspace source files;
5. run `flutter pub get`.

Imported Git projects will later use a separate Git-aware apply flow. The
`create` command always creates a new project and never modifies an existing
repository.
