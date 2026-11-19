-- =====================================================================
-- TRABALHO PRÁTICO 03 — Operadores e Funções SQL (PostgreSQL)
-- Gestão de Banco de Dados — 2º Bimestre / 2026
-- Aluno: Lucas Reis Colombo  |  RA: 007585
-- Banco: oficina_3d (Oficina de Impressão 3D sob Demanda)
-- =====================================================================
-- CONTEXTO
-- Este script continua os Trabalhos 01 e 02 e usa as mesmas tabelas
-- (cliente, material, impressora, produto, pedido, item_pedido e producao).
-- Execute antes o script_trabalho01.sql.
-- =====================================================================

-- =====================================================================
-- COMPLEMENTO DE DADOS
-- A massa do Trabalho 01 não tem pedidos nem impressões recentes, e as
-- consultas 8 e 9 filtram períodos relativos a hoje (NOW()). Por isso
-- este bloco insere um pedido de 2 dias atrás, com um item que está
-- sendo impresso há 5 horas, para essas consultas retornarem linhas.
-- =====================================================================
INSERT INTO pedido (id_cliente, data_pedido, status, forma_pagamento, valor_frete)
VALUES (9, CURRENT_DATE - 2, 'EM_PRODUCAO', 'PIX', 14.00);

INSERT INTO item_pedido (id_pedido, id_produto, quantidade, preco_unitario)
VALUES ((SELECT MAX(id_pedido) FROM pedido), 4, 3, 12.90);

INSERT INTO producao (id_item, id_impressora, data_inicio, data_fim, status)
VALUES ((SELECT MAX(id_item) FROM item_pedido), 6, NOW() - INTERVAL '5 hours', NULL, 'IMPRIMINDO');

-- =====================================================================
-- BLOCO A — OPERADORES LÓGICOS E DE COMPARAÇÃO
-- =====================================================================

-- Questão 1 — Precedência lógica com parênteses (AND, OR, ( ))
-- Problema de negócio: o time comercial quer uma lista de produtos premium,
-- ou seja, das categorias Decoração ou Utilidades que custem pelo menos R$ 60.
-- Os parênteses forçam o OR a ser avaliado antes do AND.
-- Se os parênteses fossem removidos, o AND seria avaliado primeiro e a condição
-- ficaria: Decoração (qualquer preço) OU (Utilidades E preço >= 60). O resultado
-- passaria a incluir também o "Vaso Geométrico Low Poly" (R$ 49,90), que é
-- Decoração mas não atinge o valor mínimo.
SELECT nome,
       categoria,
       preco_venda
FROM produto
WHERE (categoria = 'Decoração' OR categoria = 'Utilidades')
  AND preco_venda >= 60;

-- Questão 2 — Negação e verificação de nulos (NOT IN, IS NULL)
-- Problema de negócio: o chão de fábrica precisa ver as impressões em andamento,
-- isto é, que ainda não têm data de término (data_fim IS NULL) e que não estão
-- na fila nem falharam (NOT IN). Mostra o que está de fato sendo impresso agora.
SELECT id_producao,
       id_item,
       id_impressora,
       status,
       data_inicio
FROM producao
WHERE data_fim IS NULL
  AND status NOT IN ('FILA', 'FALHA')
ORDER BY data_inicio;

-- Questão 3 — Intervalo inclusivo e lista fechada (BETWEEN, IN)
-- Problema de negócio: montar a vitrine de "itens de entrada", com produtos de
-- preço entre R$ 20 e R$ 50 (BETWEEN inclui os dois extremos) e que sejam das
-- categorias Utilidades, Brindes ou Eletrônicos (IN).
SELECT nome,
       categoria,
       preco_venda
FROM produto
WHERE preco_venda BETWEEN 20.00 AND 50.00
  AND categoria IN ('Utilidades', 'Brindes', 'Eletrônicos')
ORDER BY preco_venda;

-- =====================================================================
-- BLOCO B — BUSCAS TEXTUAIS COM PADRÕES
-- =====================================================================

-- Questão 4a — Busca case-insensitive com curinga % (ILIKE)
-- Problema de negócio: o atendente digita "suporte" em minúsculo e precisa achar
-- todos os produtos que tenham essa palavra em qualquer posição do nome,
-- independentemente de maiúsculas ou minúsculas.
SELECT id_produto,
       nome,
       preco_venda
FROM produto
WHERE nome ILIKE '%suporte%';

-- Questão 4b — Curinga de caractere único _ (LIKE)
-- Problema de negócio: localizar a impressora cujo modelo começa com "Creality K"
-- seguido de exatamente um caractere (a linha K1, K2...). O _ aceita um único
-- caractere naquela posição, então "Creality Ender-3 V3" fica de fora.
SELECT id_impressora,
       modelo,
       status
FROM impressora
WHERE modelo LIKE 'Creality K_';

-- =====================================================================
-- BLOCO C — FUNÇÕES MATEMÁTICAS E DE TEXTO
-- =====================================================================

-- Questão 5 — Simulação de reajuste com ROUND, TRUNC, CEIL e FLOOR
-- Problema de negócio: simular um reajuste de 7,5% nos preços do catálogo e
-- comparar o valor arredondado (ROUND), o valor cortado (TRUNC) e os inteiros
-- acima e abaixo (CEIL e FLOOR), para decidir como apresentar o novo preço.
SELECT nome,
       preco_venda                                 AS preco_original,
       ROUND(preco_venda * 1.075, 2)               AS preco_arredondado,
       TRUNC(preco_venda * 1.075, 2)               AS preco_truncado,
       CEIL(preco_venda * 1.075)                   AS preco_inteiro_acima,
       FLOOR(preco_venda * 1.075)                  AS preco_inteiro_abaixo
FROM produto
ORDER BY nome;

-- Questão 6a — Classificação com MOD
-- Problema de negócio: dividir os pedidos em dois lotes de separação e embalagem
-- para duas bancadas: pedidos de número par vão para o Lote B e os ímpares para
-- o Lote A, usando o resto da divisão por 2.
SELECT id_pedido,
       status,
       CASE
           WHEN MOD(id_pedido, 2) = 0 THEN 'Lote B (par)'
           ELSE 'Lote A (ímpar)'
       END AS lote_separacao
FROM pedido
ORDER BY id_pedido;

-- Questão 6b — Sorteio com ORDER BY RANDOM() LIMIT 1
-- Problema de negócio: sortear um brinde entre os clientes que já receberam algum
-- pedido (status ENTREGUE). A cada execução o resultado pode ser outro cliente.
SELECT c.id_cliente,
       c.nome,
       c.cidade
FROM cliente c
WHERE EXISTS (SELECT 1
              FROM pedido p
              WHERE p.id_cliente = c.id_cliente
                AND p.status = 'ENTREGUE')
ORDER BY RANDOM()
LIMIT 1;

-- Questão 7 — CONCAT, UPPER/INITCAP e SPLIT_PART
-- Problema de negócio: gerar a etiqueta de contato do cliente para o envio.
-- CONCAT monta o texto sem quebrar quando o telefone é NULL (ele ignora nulos),
-- UPPER padroniza a cidade em maiúsculas, INITCAP corrige a caixa do nome e
-- SPLIT_PART separa o primeiro nome e o domínio do e-mail.
SELECT CONCAT(nome, ' - ', cidade, '/', uf, ' - Tel: ', telefone) AS etiqueta_contato,
       UPPER(cidade)                                              AS cidade_maiuscula,
       INITCAP(LOWER(nome))                                       AS nome_padronizado,
       SPLIT_PART(nome, ' ', 1)                                   AS primeiro_nome,
       SPLIT_PART(email, '@', 2)                                  AS dominio_email
FROM cliente
ORDER BY nome;

-- =====================================================================
-- BLOCO D — FUNÇÕES DE DATA/HORA E FORMATAÇÃO
-- =====================================================================

-- Questão 8a — EXTRACT e janela de período com INTERVAL
-- Problema de negócio: ver os pedidos feitos nos últimos 30 dias, separando ano,
-- mês e dia da semana (0 = domingo a 6 = sábado), para analisar a demanda recente.
SELECT id_pedido,
       data_pedido,
       EXTRACT(YEAR  FROM data_pedido) AS ano,
       EXTRACT(MONTH FROM data_pedido) AS mes,
       EXTRACT(DOW   FROM data_pedido) AS dia_da_semana,
       status
FROM pedido
WHERE data_pedido >= NOW() - INTERVAL '30 days'
ORDER BY data_pedido;

-- Questão 8b — Janela de 24 horas com DATE_TRUNC e EXTRACT de hora
-- Problema de negócio: acompanhar o que entrou em produção nas últimas 24 horas,
-- mostrando a hora de início e o dia truncado, para o supervisor do turno.
SELECT id_producao,
       id_impressora,
       status,
       EXTRACT(HOUR FROM data_inicio)    AS hora_inicio,
       DATE_TRUNC('day', data_inicio)    AS dia_inicio
FROM producao
WHERE data_inicio >= NOW() - INTERVAL '24 hours'
ORDER BY data_inicio;

-- Questão 9 — Tempo decorrido (AGE) e projeção futura (+ INTERVAL)
-- Problema de negócio: para os pedidos já entregues, calcular há quanto tempo
-- foram feitos e projetar o fim da garantia de 90 dias, somando um INTERVAL à
-- data do pedido, para o suporte saber se ainda pode atender como garantia.
SELECT p.id_pedido,
       c.nome                                         AS cliente,
       p.data_pedido,
       AGE(NOW(), p.data_pedido)                      AS tempo_desde_o_pedido,
       (p.data_pedido + INTERVAL '90 days')::DATE     AS fim_da_garantia
FROM pedido p
INNER JOIN cliente c ON c.id_cliente = p.id_cliente
WHERE p.status = 'ENTREGUE'
ORDER BY p.data_pedido;

-- Questão 10 — Relatório gerencial formatado (INNER JOIN, TO_CHAR, LPAD, FORMAT)
-- Problema de negócio: relatório para a gerência com código padronizado do pedido
-- (LPAD completa com zeros), data  no padrão brasileiro (TO_CHAR), valor no formato
-- R$ 1.234,56 (TO_CHAR e TRANSLATE trocam vírgula por ponto sem depender da
-- configuração regional do servidor) e uma frase-resumo montada com FORMAT.  
SELECT CONCAT('PED-', LPAD(p.id_pedido::TEXT, 5, '0'))                    AS codigo_pedido,
       TO_CHAR(p.data_pedido, 'DD/MM/YYYY')                               AS data_br,
       c.nome                                                             AS cliente,
       CONCAT('R$ ', TRANSLATE(TO_CHAR(SUM(i.quantidade * i.preco_unitario), 'FM999,990.00'), ',.', '.,')) AS total_itens,
       FORMAT('Pedido %s de %s — %s item(ns) — %s',
              LPAD(p.id_pedido::TEXT, 5, '0'),
              c.nome,
              SUM(i.quantidade),
              p.status)                                                   AS resumo
FROM pedido p
INNER JOIN cliente c     ON c.id_cliente = p.id_cliente
INNER JOIN item_pedido i ON i.id_pedido  = p.id_pedido
GROUP BY p.id_pedido, p.data_pedido, c.nome, p.status
ORDER BY p.id_pedido;
