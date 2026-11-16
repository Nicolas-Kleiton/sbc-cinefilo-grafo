"""Cria a base do Cinéfilo no Memgraph a partir do zero.

Apaga tudo o que houver no banco, executa cypher/01_carga.cypher e confere se o
grafo resultante tem exatamente o conteúdo da base do Mini-Projeto 3.

Uso (com o Memgraph rodando via `docker compose up -d`):

    python src/carregar.py
"""
import sys
from pathlib import Path

from neo4j import GraphDatabase

URI = "bolt://localhost:7687"
AUTH = ("", "")  # o Memgraph não exige autenticação por padrão
ARQUIVO_CARGA = Path(__file__).resolve().parent.parent / "cypher" / "01_carga.cypher"

# Conteúdo esperado, conferido contra o cinema.ttl do Mini-Projeto 3
NOS_ESPERADOS = {
    "Obra": 17, "Filme": 17,
    "Pessoa": 36, "Profissional": 36,
    "Diretor": 10, "Ator": 19, "Roteirista": 3, "Compositor": 4,
    "Organizacao": 8, "Estudio": 8,
    "Premio": 7,
    "Genero": 7,
}
RELACIONAMENTOS_ESPERADOS = {
    "DO_GENERO": 21, "SUBGENERO_DE": 5, "DISJUNTO_DE": 1,
    "DIRIGIDO_POR": 19, "ROTEIRIZADO_POR": 12, "TEM_NO_ELENCO": 27,
    "TRILHA_SONORA_DE": 11, "PRODUZIDO_POR": 23, "GANHOU": 16,
    "SEQUENCIA_DE": 3, "INFLUENCIOU": 3, "COLABOROU_COM": 8,
}
TOTAL_NOS = 75
TOTAL_RELACIONAMENTOS = 149


def comandos(texto):
    """Separa o arquivo .cypher em comandos, descartando as linhas de comentário."""
    linhas = [linha for linha in texto.splitlines() if not linha.strip().startswith("//")]
    return [c.strip() for c in "\n".join(linhas).split(";") if c.strip()]


def executar(driver, cypher):
    registros, _, _ = driver.execute_query(cypher, database_="memgraph")
    return registros


def carregar(driver, verbose=True):
    """Apaga o banco, cria restrições e grafo, e confere o resultado."""
    executar(driver, "MATCH (n) DETACH DELETE n")
    for comando in comandos(ARQUIVO_CARGA.read_text(encoding="utf-8")):
        if comando.startswith("CREATE CONSTRAINT"):
            try:
                executar(driver, comando)
            except Exception as erro:  # a restrição já existe de uma carga anterior
                if verbose:
                    print(f"Restrição mantida ({type(erro).__name__}): {comando}")
            continue
        executar(driver, comando)
    return conferir(driver, verbose)


def contagens(driver):
    nos = {r["rotulo"]: r["n"] for r in executar(
        driver, "MATCH (n) UNWIND labels(n) AS rotulo RETURN rotulo, count(*) AS n")}
    rels = {r["tipo"]: r["n"] for r in executar(
        driver, "MATCH ()-[r]->() RETURN type(r) AS tipo, count(*) AS n")}
    total_nos = executar(driver, "MATCH (n) RETURN count(n) AS n")[0]["n"]
    total_rels = executar(driver, "MATCH ()-[r]->() RETURN count(r) AS n")[0]["n"]
    return nos, rels, total_nos, total_rels


def conferir(driver, verbose=True):
    """Compara o grafo no banco com o conteúdo esperado. Devolve True se bater."""
    nos, rels, total_nos, total_rels = contagens(driver)
    ok = True
    linhas = []
    for nome, esperado in list(NOS_ESPERADOS.items()) + list(RELACIONAMENTOS_ESPERADOS.items()):
        obtido = nos.get(nome, rels.get(nome, 0))
        ok &= obtido == esperado
        tipo = "rótulo" if nome in NOS_ESPERADOS else "relacionamento"
        linhas.append(f"  {tipo:<15}{nome:<18}{obtido:>5}{esperado:>10}  {'ok' if obtido == esperado else 'DIFERENTE'}")
    ok &= total_nos == TOTAL_NOS and total_rels == TOTAL_RELACIONAMENTOS
    if verbose:
        print(f"  {'tipo':<15}{'nome':<18}{'no banco':>5}{'esperado':>10}")
        print("\n".join(linhas))
        print(f"\n  Total: {total_nos} nós (esperado {TOTAL_NOS}), "
              f"{total_rels} relacionamentos (esperado {TOTAL_RELACIONAMENTOS})")
        print("  Base completa." if ok else "  ATENÇÃO: a base difere do esperado.")
    return ok


if __name__ == "__main__":
    with GraphDatabase.driver(URI, auth=AUTH) as driver:
        driver.verify_connectivity()
        print(f"Carregando {ARQUIVO_CARGA.name} em {URI}...\n")
        sys.exit(0 if carregar(driver) else 1)
