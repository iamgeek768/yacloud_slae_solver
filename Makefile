# Обёртки над основными действиями. Примеры:
#   make test
#   make matrix N=10000 && make upload && make run
#   make results RUN=<run_id> && make verify RUN=<run_id>
# Показательная система из трёх уравнений:
#   make example && make upload MATRIX=data/example_3x3.bin && make run
#   make results RUN=<run_id> && make show RUN=<run_id> MATRIX=data/example_3x3.bin

N         ?= 2000
DOMINANCE ?= 1.1
MATRIX    ?= data/matrix.bin
NP        ?=
THREADS   ?=

.PHONY: test matrix example deploy wait start stop upload run results verify show grafana grafana-down destroy

test:
	tests/test_local.sh

matrix:
	mkdir -p data
	python3 tools/gen_matrix.py --n $(N) --dominance $(DOMINANCE) --out $(MATRIX) --x-true data/x_true.bin

example:
	python3 tools/example_3x3.py

deploy:
	scripts/tf.sh apply

wait:
	scripts/wait_cluster.sh

start:
	scripts/cluster_power.sh start

stop:
	scripts/cluster_power.sh stop

upload:
	scripts/upload_matrix.sh $(MATRIX)

run:
	scripts/cluster_run.sh $(NP) $(THREADS)

results:
	scripts/fetch_results.sh $(RUN)

verify:
	python3 tools/verify.py --matrix $(MATRIX) --x results/$(RUN)/x.bin --x-true data/x_true.bin

show:
	python3 tools/show_result.py results/$(RUN) --matrix $(MATRIX)

grafana:
	scripts/grafana.sh up

grafana-down:
	scripts/grafana.sh down

destroy:
	scripts/tf.sh destroy
