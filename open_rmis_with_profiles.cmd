@echo off
REM Launch VS Code for this project with a workspace-scoped DBT_PROFILES_DIR

set "DBT_PROFILES_DIR=C:\work_folder\my_dbt_project\.dbt"
set "PROJECT_DIR=C:\work_folder\my_dbt_project"

REM Open in the same VS Code window if one exists; remove --reuse-window if you prefer new window
code --reuse-window "%PROJECT_DIR%"
