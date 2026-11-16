# Cinéfilo: a base do MP3 como grafo de propriedades no Memgraph

A base de conhecimento sobre cinema do Mini-Projeto 3
([sbc-cinefilo-ontologia](https://github.com/Nicolas-Kleiton/sbc-cinefilo-ontologia)), remodelada
como **grafo de propriedades**, guardada no **Memgraph** e consultada com **Cypher** a partir do notebook
[`Cinefilo_Grafo.ipynb`](Cinefilo_Grafo.ipynb).

Mini-Projeto 4 — Sistemas Baseados em Conhecimento (UFPB).

## Resumo do modelo

No MP3, a base era um conjunto de triplas RDF com um esquema em RDFS e OWL. Aqui o mesmo conteúdo vira
**nós** com **rótulos** e **propriedades**, ligados por **relacionamentos**:

```
(:Obra:Filme {id, titulo, ano, duracao, nota})
   -[:DO_GENERO]->           (:Genero {id, nome}) -[:SUBGENERO_DE]-> (:Genero)
   -[:DIRIGIDO_POR]->        (:Pessoa:Profissional:Diretor {id, nome, nascimento, nacionalidade})
   -[:TEM_NO_ELENCO]->       (:Pessoa:Profissional:Ator ...)
   -[:ROTEIRIZADO_POR]->     (:Pessoa:Profissional:Roteirista ...)
   -[:TRILHA_SONORA_DE]->    (:Pessoa:Profissional:Compositor ...)
   -[:PRODUZIDO_POR]->       (:Organizacao:Estudio {id, nome, fundacao, pais})
   -[:GANHOU {ano}]->        (:Premio {id, nome})
   -[:SEQUENCIA_DE]->        (:Filme)

(:Pessoa)-[:INFLUENCIOU]->(:Pessoa)
(:Pessoa)-[:COLABOROU_COM]->(:Pessoa)
(:Genero {id: 'Ficcao'})-[:DISJUNTO_DE]->(:Genero {id: 'Documentario'})
```

| Elemento | Quantidade |
|---|---|
| Filmes | 17 |
| Pessoas | 36 (10 diretores, 19 atores, 3 roteiristas, 4 compositores) |
| Estúdios | 8 |
| Prêmios | 7 |
| Gêneros | 7 |
| **Nós** | **75** |
| **Relacionamentos** | **149**, de 12 tipos |

As 68 instâncias do MP3 (filmes, pessoas, estúdios e prêmios) estão todas no grafo, com os mesmos
valores. O `src/carregar.py` confere essas contagens a cada carga.

### Principais decisões

- **Os gêneros são nós, não rótulos.** No MP3, `Drama` era uma classe, subclasse de `Ficcao`. Aqui é um
  nó `(:Genero)` ligado por `SUBGENERO_DE`. Assim a taxonomia continua no grafo, e "filmes de ficção"
  vira uma travessia: `-[:DO_GENERO]->()-[:SUBGENERO_DE*]->(:Genero {id: 'Ficcao'})`.
- **As outras hierarquias viram rótulos empilhados.** Um diretor é `:Pessoa:Profissional:Diretor`, como
  `Diretor ⊂ Profissional ⊂ Pessoa`; um filme é `:Obra:Filme`; um estúdio é `:Organizacao:Estudio`.
  Cada pessoa tem o rótulo do papel declarado no MP3.
- **O `id` faz o papel da URI.** `cine:interestelar` vira `{id: 'interestelar'}`, e uma restrição de
  unicidade impede ids repetidos.
- **Propriedade na aresta.** O ano em que cada prêmio foi entregue fica no relacionamento:
  `-[:GANHOU {ano: 2015}]->`. Em RDF isso exigiria reificação; no grafo de propriedades é nativo.

## Do RDF/OWL ao grafo de propriedades

O Memgraph não tem reasoner. Tudo o que no MP3 era deduzido pelo OWL é resolvido aqui **pela própria
consulta**, percorrendo o grafo:

| No MP3 | No MP4 |
|---|---|
| `rdfs:subClassOf` (gêneros) | hierarquia `SUBGENERO_DE`, percorrida com `*` |
| `rdfs:subClassOf` (pessoas, obras) | rótulos empilhados no mesmo nó |
| `rdfs:domain` / `rdfs:range` | o papel de cada pessoa é lido pelo relacionamento que chega nela |
| `owl:inverseOf` | desnecessário: a mesma aresta é percorrida nos dois sentidos |
| `owl:TransitiveProperty` | caminho de tamanho variável, `[:INFLUENCIOU*]` |
| `owl:SymmetricProperty` | relacionamento consultado sem direção, `-[:COLABOROU_COM]-` |
| `rdfs:subPropertyOf` + transitiva | caminho `[:SEQUENCIA_DE*]` ("posterior na franquia") |
| `owl:FunctionalProperty` | garantida pelo modelo: uma propriedade de nó guarda um único valor |
| `owl:disjointWith` | relacionamento `DISJUNTO_DE` e consulta de verificação (V1) |
| `owl:AsymmetricProperty` | consulta de verificação de ciclos (V2) |
| `owl:equivalentClass` (schema.org) | exportação do catálogo em JSON-LD do schema.org (S10) |

## Consultas

O notebook executa **todas as consultas do MP3 reescritas em Cypher** e imprime cada resultado com o
número e o propósito. O arquivo [`cypher/02_consultas.cypher`](cypher/02_consultas.cypher) tem as
mesmas consultas, prontas para colar no Memgraph Lab.

| Seção | Consultas | Conteúdo |
|---|---|---|
| 2 | M1 a M3 | conferência da carga, rótulos, esquema e hierarquia de gêneros |
| 3 | T1 a T7 | as consultas `g.triples()` do MP3 (Parte 1) |
| 4 | I1 a I6, V1, V2 | o que era inferência vira consulta, e as verificações de consistência |
| 5 | S1 a S13 | as consultas SPARQL do MP3 (Parte 2) |

Correspondência das consultas SPARQL:

| # | No MP3 | Em Cypher |
|---|---|---|
| S1 | SELECT + FILTER | `MATCH ... WHERE`, com travessia pela hierarquia de gêneros |
| S2 | ORDER BY + LIMIT | `ORDER BY ... LIMIT` |
| S3 | agregação + HAVING | `count`, `avg`, `min`, `max` + `WITH ... WHERE` |
| S4 | agregação por gênero | `count`, `avg`, com travessia |
| S5 | VALUES + GROUP_CONCAT | `CASE` + `collect` |
| S6 | OPTIONAL | `OPTIONAL MATCH`, com o ano do prêmio lido da aresta |
| S7 | caminho `influenciou+` | caminho variável `[:INFLUENCIOU*]` |
| S8 | ASK, antes × depois | `count(*) > 0`, com um salto × com caminho |
| S9 | ASK | `count(*) > 0`, com travessia |
| S10 | CONSTRUCT para schema.org | mapa JSON-LD do schema.org |
| S11 | INSERT DATA | `CREATE` |
| S12 | DELETE/INSERT | `SET` |
| S13 | DELETE | `DETACH DELETE` |

**Consultas com travessia** (dois ou mais relacionamentos encadeados): S1, S4, S7, S8, S9, I1, I4, I6
e V1.

**Atualizações:** S11, S12 e S13 rodam dentro de uma transação. O notebook mostra o estado antes e
depois de cada uma e, no fim, desfaz tudo com `rollback`. Assim o efeito aparece na saída e a base no
Memgraph continua igual à carga.

## Como executar

Requer **Docker** (Docker Desktop com WSL 2 no Windows, ou Docker Engine com o plugin Compose no Linux)
e **Python 3.10** ou mais recente.

### 1. Subir o Memgraph

```bash
git clone https://github.com/Nicolas-Kleiton/sbc-cinefilo-grafo.git
cd sbc-cinefilo-grafo

docker compose up -d
docker compose ps        # os containers memgraph e memgraph-lab devem estar em execução
```

- Memgraph: `bolt://localhost:7687` (é por aqui que o Python conecta)
- Memgraph Lab: [http://localhost:3000](http://localhost:3000) (interface para consultar e ver o grafo)

### 2. Instalar as dependências

```bash
python -m venv .venv
# Windows:      .venv\Scripts\activate
# Linux/macOS:  source .venv/bin/activate

pip install -r requirements.txt
```

### 3. Carregar a base

```bash
python src/carregar.py
```

O script apaga o banco, executa `cypher/01_carga.cypher` e confere cada rótulo e cada tipo de
relacionamento. A saída deve terminar com `Base completa.`

### 4. Executar as consultas

```bash
jupyter notebook Cinefilo_Grafo.ipynb
```

No Jupyter, use **Run → Run All Cells**. No VS Code, abra o notebook, escolha o kernel do `.venv` em
**Select Kernel** e clique em **Run All**. O notebook precisa ser aberto a partir da pasta do
repositório, porque importa o `src/carregar.py`. Se o banco estiver vazio, a seção 2 faz a carga.

O Colab não serve aqui: ele não alcança o Memgraph rodando no seu computador.

### Teste de persistência

O Memgraph mantém o grafo em memória e grava snapshots e um log de escrita antecipada (WAL) em
`/var/lib/memgraph`. O volume `mg_lib` guarda esses arquivos fora do container.

```bash
docker compose restart memgraph
```

Depois, no Memgraph Lab ou no notebook, `MATCH (n) RETURN count(n)` deve continuar devolvendo **75**. A
seção 2 do notebook também mostra isso: com a base já existente, ela só confere, sem recarregar.

> `docker compose down` preserva o volume e a base. `docker compose down -v` remove o volume e **apaga a
> base**; nesse caso, basta rodar `python src/carregar.py` de novo.

### Visualizar no Memgraph Lab

Em [http://localhost:3000](http://localhost:3000), consultas que devolvem caminhos desenham o grafo.
Por exemplo, a cadeia de influência e os filmes de Nolan:

```cypher
MATCH p = (:Pessoa {id: 'kubrick'})-[:INFLUENCIOU*]->(:Pessoa)
RETURN p;

MATCH p = (:Pessoa {id: 'nolan'})<-[:DIRIGIDO_POR]-(:Filme)-[:DO_GENERO]->(:Genero)
RETURN p;
```

## Estrutura do repositório

| Arquivo | Conteúdo |
|---|---|
| `docker-compose.yml` | Sobe o Memgraph e o Memgraph Lab |
| `cypher/01_carga.cypher` | A base inteira em Cypher: restrições, nós e relacionamentos |
| `cypher/02_consultas.cypher` | Todas as consultas, para executar no Memgraph Lab |
| `src/carregar.py` | Script de carga: cria a base do zero e confere o resultado |
| `Cinefilo_Grafo.ipynb` | Aplicação de consultas: conecta ao Memgraph e executa todas as consultas |
| `requirements.txt` | Dependências Python |

## Licença

[MIT](LICENSE)
