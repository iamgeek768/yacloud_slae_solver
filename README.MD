# Запуск космолета

## Логинимся, запускаем terraform и развертывание
1. `yc init`
2. `Проверка yc config list`
3. `scripts/tf.sh init`
4. `make start`

## Запуск калькулирования

5. `make run`
6. Скачать ответ кластера из облака `make results RUN=<RUN_ID>`

## Запуск проверки расчетаИспользование:
    python3 tools/example_3x3.py                 
    make upload MATRIX=data/example_3x3.bin     

7. `make matrix N=10000` (размерность матрицы)
8. `make verify RUN=<RUN_ID>`

## Графана

9. `make grafana` (http://localhost:3000/d/slae-cluster)

## Остановка

10. `make stop`

# Замена матрицы в бакете

## Случайная матрица размерности N в бакете

1. Новая система `make matrix N=15000` 
2. Грузим в бакет `make upload` 

Дальше `make run` и т д

## Простой пример матрица 3 на 3

1. Cоздать data/example_3x3.bin `make example`                                        
2. Отправить в облако `make upload MATRIX=data/example_3x3.bin`       
3. `make run`                                             
4. `make results RUN=<номер>`                            
5. Распаковать и показать `make show RUN=<номер> MATRIX=data/example_3x3.bin`   

