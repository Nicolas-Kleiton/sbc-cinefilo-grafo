// =============================================================================
//  Cinéfilo: todas as consultas do notebook, para executar no Memgraph Lab
//  (http://localhost:3000). Cada consulta termina em ';'. A ordem é a do
//  notebook: T, I, V e S.
//
//  ATENÇÃO: S11, S12 e S13 ALTERAM a base e por isso ficam no fim do arquivo.
//  No notebook elas rodam numa transação desfeita no fim; aqui, depois de
//  executá-las, recarregue a base com `python src/carregar.py`.
// =============================================================================

// [T1] Elenco de Interestelar  (nó fixo, relacionamento fixo, destino livre)
MATCH (:Filme {id: 'interestelar'})-[:TEM_NO_ELENCO]->(a:Pessoa)
RETURN a.nome AS ator
ORDER BY ator;

// [T2] Filmes dirigidos por Denis Villeneuve  (origem livre, relacionamento e destino fixos)
MATCH (f:Filme)-[:DIRIGIDO_POR]->(:Pessoa {id: 'villeneuve'})
RETURN f.titulo AS filme
ORDER BY filme;

// [T3] Cinco maiores notas no IMDb  (propriedade fixa, nós livres)
MATCH (f:Filme)
WHERE f.nota IS NOT NULL
RETURN f.titulo AS filme, f.nota AS nota
ORDER BY nota DESC, filme
LIMIT 5;

// [T4] Tudo o que sai do nó de Clint Eastwood  (nó fixo, o resto livre)
MATCH (p:Pessoa {id: 'eastwood'})
OPTIONAL MATCH (p)-[r]->(x)
RETURN labels(p) AS rotulos, properties(p) AS propriedades,
       collect(type(r) + ' -> ' + coalesce(x.nome, x.titulo)) AS relacionamentos_de_saida;

// [T5] Onde Clint Eastwood aparece como destino  (destino fixo, o resto livre)
MATCH (x)-[r]->(:Pessoa {id: 'eastwood'})
RETURN x.titulo AS origem, type(r) AS relacionamento
ORDER BY relacionamento;

// [T6] Que relacionamento liga Nolan a Villeneuve  (origem e destino fixos)
MATCH (:Pessoa {id: 'nolan'})-[r]->(:Pessoa {id: 'villeneuve'})
RETURN type(r) AS relacionamento;

// [T7] Filmes ligados diretamente ao gênero Ficção  (sem percorrer a hierarquia)
MATCH (f:Filme)-[:DO_GENERO]->(:Genero {id: 'Ficcao'})
RETURN count(f) AS filmes;

// ----- O que era inferência vira consulta (direto x com a regra) -----

// [I1] rdfs:subClassOf  ->  caminho SUBGENERO_DE*: que filmes são de Ficção?  (direto)
MATCH (f:Filme)-[:DO_GENERO]->(:Genero {id: 'Ficcao'})
RETURN f.titulo AS nome;
// [I1] com a regra
MATCH (f:Filme)-[:DO_GENERO]->(:Genero)-[:SUBGENERO_DE*]->(:Genero {id: 'Ficcao'})
RETURN DISTINCT f.titulo AS nome;

// [I2] rdfs:domain / rdfs:range  ->  papel pelo relacionamento: quais são os papéis de Christopher Nolan?  (direto)
MATCH (p:Pessoa {id: 'nolan'})
UNWIND labels(p) AS nome
RETURN nome;
// [I2] com a regra
MATCH (p:Pessoa {id: 'nolan'})
UNWIND labels(p) AS nome
RETURN nome
UNION
MATCH (:Pessoa {id: 'nolan'})<-[r]-(:Filme)
RETURN CASE type(r)
         WHEN 'DIRIGIDO_POR' THEN 'Diretor'
         WHEN 'TEM_NO_ELENCO' THEN 'Ator'
         WHEN 'ROTEIRIZADO_POR' THEN 'Roteirista'
         WHEN 'TRILHA_SONORA_DE' THEN 'Compositor'
       END AS nome;

// [I3] owl:inverseOf  ->  a mesma aresta, percorrida ao contrário: o que Christopher Nolan dirigiu?  (direto)
MATCH (f:Filme)-[:DIRIGIDO_POR]->(:Pessoa {id: 'nolan'})
RETURN f.titulo AS nome;
// [I3] com a regra
MATCH (:Pessoa {id: 'nolan'})<-[:DIRIGIDO_POR]-(f:Filme)
RETURN f.titulo AS nome;

// [I4] owl:TransitiveProperty  ->  caminho INFLUENCIOU*: quem Stanley Kubrick influenciou?  (direto)
MATCH (:Pessoa {id: 'kubrick'})-[:INFLUENCIOU]->(x:Pessoa)
RETURN x.nome AS nome;
// [I4] com a regra
MATCH (:Pessoa {id: 'kubrick'})-[:INFLUENCIOU*]->(x:Pessoa)
RETURN DISTINCT x.nome AS nome;

// [I5] owl:SymmetricProperty  ->  relacionamento sem direção: com quem Hans Zimmer colaborou?  (direto)
MATCH (:Pessoa {id: 'zimmer'})-[:COLABOROU_COM]->(x:Pessoa)
RETURN x.nome AS nome;
// [I5] com a regra
MATCH (:Pessoa {id: 'zimmer'})-[:COLABOROU_COM]-(x:Pessoa)
RETURN x.nome AS nome;

// [I6] rdfs:subPropertyOf + transitiva  ->  caminho SEQUENCIA_DE*: Toy Story 3 vem depois de quais filmes?  (direto)
MATCH (:Filme {id: 'toyStory3'})-[:SEQUENCIA_DE]->(x:Filme)
RETURN x.titulo AS nome;
// [I6] com a regra
MATCH (:Filme {id: 'toyStory3'})-[:SEQUENCIA_DE*]->(x:Filme)
RETURN DISTINCT x.titulo AS nome;

// ----- Verificações de consistência -----

// [V1] Verificação de owl:disjointWith: filmes em dois gêneros disjuntos
MATCH (f:Filme)-[:DO_GENERO]->(g:Genero)
OPTIONAL MATCH (g)-[:SUBGENERO_DE*]->(acima:Genero)
WITH f, collect(DISTINCT g) + collect(DISTINCT acima) AS categorias
MATCH (a:Genero)-[:DISJUNTO_DE]->(b:Genero)
WHERE a IN categorias AND b IN categorias
RETURN f.titulo AS filme, a.nome AS categoria_1, b.nome AS categoria_2;

// [V2] Verificação de owl:AsymmetricProperty: sequências em ciclo, de qualquer tamanho
//      (laço de um filme nele mesmo, par A -> B -> A, ou cadeias maiores).
//      O WHERE faz cada ciclo começar pelo menor id, para aparecer uma vez só.
MATCH p = (a:Filme)-[:SEQUENCIA_DE*]->(a)
WHERE all(n IN nodes(p) WHERE a.id <= n.id)
RETURN reduce(s = a.titulo, n IN tail(nodes(p)) | s + ' -> ' + n.titulo) AS ciclo,
       size(relationships(p)) AS filmes_no_ciclo;

// [S1] Ficção lançada a partir de 2010 com nota ≥ 8.3  (WHERE; travessia)
MATCH (f:Filme)-[:DO_GENERO]->(:Genero)-[:SUBGENERO_DE*]->(:Genero {id: 'Ficcao'})
WITH DISTINCT f
WHERE f.ano >= 2010 AND f.nota >= 8.3
MATCH (f)-[:DIRIGIDO_POR]->(d:Pessoa)
RETURN f.titulo AS filme, f.ano AS ano, f.nota AS nota, d.nome AS diretor
ORDER BY nota DESC, ano;

// [S2] Os 5 filmes mais longos  (ORDER BY + LIMIT)
MATCH (f:Filme)
RETURN f.titulo AS filme, f.duracao AS duracao, f.ano AS ano
ORDER BY duracao DESC
LIMIT 5;

// [S3] Diretores com 2+ filmes: quantidade, nota média e período  (agregação)
MATCH (f:Filme)-[:DIRIGIDO_POR]->(d:Pessoa)
WITH d, count(f) AS filmes, round(avg(f.nota) * 100) / 100.0 AS media,
     min(f.ano) AS primeiro, max(f.ano) AS ultimo
WHERE filmes >= 2
RETURN d.nome AS diretor, filmes, media, primeiro, ultimo
ORDER BY media DESC, filmes DESC, diretor;

// [S4] Filmes e nota média por gênero de ficção  (agregação; travessia)
//      Um salto de SUBGENERO_DE, sem '*': agrupa pelos subgêneros DIRETOS de Ficção,
//      que hoje são todos os gêneros de ficção, porque a taxonomia tem um só nível.
MATCH (f:Filme)-[:DO_GENERO]->(g:Genero)-[:SUBGENERO_DE]->(:Genero {id: 'Ficcao'})
RETURN g.nome AS genero, count(f) AS filmes, round(avg(f.nota) * 100) / 100.0 AS media
ORDER BY filmes DESC, media DESC;

// [S5] Profissionais que acumulam mais de um papel  (CASE + collect)
MATCH (p:Pessoa)<-[r]-(:Filme)
WITH DISTINCT p, CASE type(r)
                   WHEN 'DIRIGIDO_POR' THEN 'Diretor'
                   WHEN 'TEM_NO_ELENCO' THEN 'Ator'
                   WHEN 'ROTEIRIZADO_POR' THEN 'Roteirista'
                   WHEN 'TRILHA_SONORA_DE' THEN 'Compositor'
                 END AS papel
WITH p, papel ORDER BY papel
WITH p, collect(papel) AS papeis
WHERE size(papeis) > 1
RETURN p.nome AS pessoa,
       [l IN labels(p) WHERE l IN ['Diretor', 'Ator', 'Roteirista', 'Compositor']] AS declarado,
       papeis
ORDER BY pessoa;

// [S6] Ficção científica e prêmios recebidos, quando houver  (OPTIONAL MATCH)
MATCH (f:Filme)-[:DO_GENERO]->(:Genero {id: 'FiccaoCientifica'})
OPTIONAL MATCH (f)-[g:GANHOU]->(p:Premio)
RETURN f.titulo AS filme, f.ano AS ano, p.nome AS premio, g.ano AS cerimonia
ORDER BY ano, premio;

// [S7] Diretores influenciados por Kubrick, direta ou indiretamente  (caminho variável; travessia)
MATCH (:Pessoa {id: 'kubrick'})-[r:INFLUENCIOU*]->(x:Pessoa)
RETURN x.nome AS influenciado, x.nascimento AS nascimento, size(r) AS saltos
ORDER BY nascimento;

// [S8a] Kubrick influenciou Villeneuve diretamente?  (ASK: um salto)
MATCH (:Pessoa {id: 'kubrick'})-[:INFLUENCIOU]->(:Pessoa {id: 'villeneuve'})
RETURN count(*) > 0 AS resposta;

// [S8b] Kubrick influenciou Villeneuve, por qualquer caminho?  (ASK: caminho variável; travessia)
MATCH (:Pessoa {id: 'kubrick'})-[:INFLUENCIOU*]->(:Pessoa {id: 'villeneuve'})
RETURN count(*) > 0 AS resposta;

// [S9] Existe alguém que atuou em um filme que ele mesmo dirigiu?  (ASK; travessia)
MATCH (p:Pessoa)<-[:DIRIGIDO_POR]-(:Filme)-[:TEM_NO_ELENCO]->(p)
RETURN count(*) > 0 AS resposta;

// [S10] Exportação do catálogo no formato schema.org (JSON-LD)  (equivalente ao CONSTRUCT)
MATCH (f:Filme)
OPTIONAL MATCH (f)-[:DIRIGIDO_POR]->(d:Pessoa)
WITH f, collect(DISTINCT d) AS diretores
OPTIONAL MATCH (f)-[:TEM_NO_ELENCO]->(a:Pessoa)
WITH f, diretores, collect(DISTINCT a) AS atores
RETURN {
  `@context`: 'https://schema.org',
  `@type`: 'Movie',
  `@id`: f.id,
  name: f.titulo,
  datePublished: f.ano,
  duration: 'PT' + toString(f.duracao) + 'M',
  director: [d IN diretores | {`@type`: 'Person', name: d.nome}],
  actor: [a IN atores | {`@type`: 'Person', name: a.nome}]
} AS filme;

// ----- Atualizações: alteram a base -----

// [S11] CREATE: cadastrar o filme Tenet (Nolan, 2020)
MATCH (nolan:Pessoa {id: 'nolan'}), (goransson:Pessoa {id: 'goransson'}),
      (warner:Estudio {id: 'warner'}),
      (fc:Genero {id: 'FiccaoCientifica'}), (acao:Genero {id: 'Acao'})
CREATE (tenet:Obra:Filme {id: 'tenet', titulo: 'Tenet', ano: 2020, duracao: 150, nota: 7.3}),
       (washington:Pessoa:Profissional:Ator {id: 'washington', nome: 'John David Washington',
                                             nascimento: 1984, nacionalidade: 'EUA'}),
       (pattinson:Pessoa:Profissional:Ator {id: 'pattinson', nome: 'Robert Pattinson',
                                            nascimento: 1986, nacionalidade: 'Reino Unido'}),
       (tenet)-[:DO_GENERO]->(fc),
       (tenet)-[:DO_GENERO]->(acao),
       (tenet)-[:DIRIGIDO_POR]->(nolan),
       (tenet)-[:ROTEIRIZADO_POR]->(nolan),
       (tenet)-[:TEM_NO_ELENCO]->(washington),
       (tenet)-[:TEM_NO_ELENCO]->(pattinson),
       (tenet)-[:TRILHA_SONORA_DE]->(goransson),
       (tenet)-[:PRODUZIDO_POR]->(warner);

// [S12] SET: atualizar a nota de Tenet para 7.4  (equivalente ao DELETE/INSERT)
MATCH (f:Filme {id: 'tenet'})
SET f.nota = 7.4;

// [S13] DETACH DELETE: modo família, remover filmes de terror  (equivalente ao DELETE)
MATCH (f:Filme)-[:DO_GENERO]->(:Genero {id: 'Terror'})
DETACH DELETE f;
