# GitHub Actions Workflows

## Установка workflows

GitHub требует специальные права для создания workflow файлов через OAuth. Есть два способа:

### Способ 1: Через веб-интерфейс GitHub (рекомендуется)

1. Откройте репозиторий на GitHub: https://github.com/borzov/MegaplanHelper
2. Нажмите "Add file" → "Create new file"
3. Создайте файл `.github/workflows/release.yml` и скопируйте содержимое из локального файла
4. Создайте файл `.github/workflows/build.yml` и скопируйте содержимое из локального файла
5. Нажмите "Commit new file"

### Способ 2: Использовать Personal Access Token

1. Создайте Personal Access Token на GitHub:
   - Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Создайте новый token с правами `repo` и `workflow`
2. Используйте token для push:
   ```bash
   git remote set-url origin https://YOUR_TOKEN@github.com/borzov/MegaplanHelper.git
   git push origin master
   ```

## Что делают workflows

### build.yml
- Запускается при каждом push в master
- Проверяет, что проект компилируется

### release.yml
- Запускается при создании тега версии (v*)
- Автоматически собирает универсальный бинарник
- Создает ZIP-архив с приложением
- Прикрепляет архив к GitHub Release

