Показ цен рецептов (предмета, суммы реагентов) в окне врофессий.

Измененный мод LilSparkysWorkshop https://github.com/laytya/LilSparkysWorkshop-vanilla v2.0.1 для WoW версии 3.3.5+ сервера Sirus.

  В окне профессии мода Skillet - работает.
  В окне рецептов мода AckisRecipeList (все рецепты, включая неизученные) - работает базово.
    Обновление базы рецептов из открытого окна профессии ARL,
    вызовом функции "/run UpdateRdbSkills()" для каждой профессии отдельно.
  Обновление цен в базе работает, вызовом функции "/run UpdateRdbPrices()".

  Запуск:
  1. Cкопировать папки LilSparkysWorkshop и AckisRecipeList в \Interface\Addons\ (в папке игры).
  2. Открыть окно ARL на нужной профессии, в чате игры "/run UpdateRdbSkills()" один раз для каждой профессии.
  3. В чате "/run UpdateRdbPrices()"  каждый раз для обновления цен, потом будет кнопка.
