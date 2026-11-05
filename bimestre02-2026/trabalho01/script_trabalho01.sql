-- =====================================================================
-- TRABALHO PRÁTICO 01 — Gestão de Banco de Dados (PostgreSQL)
-- 2º Bimestre / 2026
-- Aluno: Lucas Reis Colombo  |  RA: 007585
-- Banco: oficina_3d
-- =====================================================================
-- JUSTIFICATIVA DA ESCOLHA DO TEMA
-- Escolhi o domínio "Oficina de Impressão 3D sob Demanda". É um negócio
-- real e em expansão: o cliente escolhe um produto de um catálogo, a
-- oficina imprime sob encomenda, controla o estoque de filamentos/resina
-- e a ocupação das impressoras. O domínio é rico em relacionamentos
-- (cliente → pedido → item → produção → impressora; produto → material),
-- o que permite explorar chaves, restrições e consultas analíticas, e
-- serve de base para as atividades práticas seguintes do semestre.
--
-- CONTEXTUALIZAÇÃO DO NEGÓCIO
-- A oficina recebe pedidos de clientes (pessoas físicas e pequenas
-- empresas). Cada pedido tem um ou mais itens (produtos do catálogo).
-- Cada produto é feito em um material específico (PLA, PETG, ABS, TPU ou
-- resina). Cada item pedido gera uma ou mais ordens de produção, que são
-- executadas em uma impressora. Falhas de impressão geram reimpressão,
-- por isso um item pode ter várias linhas de produção.


DROP TABLE IF EXISTS producao, item_pedido, pedido, produto, impressora, material, cliente CASCADE;


-- Tabela CLIENTE
-- Objetivo: guardar quem compra da oficina. É a base do relacionamento
-- comercial: permite identificar, contatar e entregar os pedidos, além
-- de analisar o perfil de compra por cidade/estado.

CREATE TABLE cliente (
    id_cliente     SERIAL       PRIMARY KEY,
    nome           VARCHAR(100) NOT NULL,
    email          VARCHAR(120) NOT NULL UNIQUE,
    telefone       VARCHAR(20),
    cidade         VARCHAR(60)  NOT NULL,
    uf             CHAR(2)      NOT NULL,
    data_cadastro  DATE         NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT ck_cliente_email CHECK (email LIKE '%@%.%')
);

-- Tabela MATERIAL
-- Objetivo: controlar a matéria-prima (filamentos e resina): tipo, cor,
-- marca, custo por kg e estoque em gramas. Serve para calcular o custo de
-- cada produto e para alertar sobre estoque baixo.

CREATE TABLE material (
    id_material  SERIAL        PRIMARY KEY,
    tipo         VARCHAR(10)   NOT NULL,
    cor          VARCHAR(30)   NOT NULL,
    marca        VARCHAR(40)   NOT NULL DEFAULT 'Genérica',
    preco_kg     NUMERIC(8,2)  NOT NULL,
    estoque_g    INTEGER       NOT NULL DEFAULT 0,
    CONSTRAINT uq_material_tipo_cor UNIQUE (tipo, cor),
    CONSTRAINT ck_material_tipo     CHECK (tipo IN ('PLA','PETG','ABS','TPU','RESINA')),
    CONSTRAINT ck_material_preco    CHECK (preco_kg > 0),
    CONSTRAINT ck_material_estoque  CHECK (estoque_g >= 0)
);

-- Tabela IMPRESSORA
-- Objetivo: cadastrar o parque de máquinas da oficina (modelo, tecnologia
-- FDM ou SLA, volume de impressão, situação e data de aquisição). Permite
-- saber quais máquinas estão disponíveis e medir a utilização de cada uma.

CREATE TABLE impressora (
    id_impressora   SERIAL       PRIMARY KEY,
    modelo          VARCHAR(60)  NOT NULL UNIQUE,
    tecnologia      VARCHAR(5)   NOT NULL,
    volume_max_mm   VARCHAR(20)  NOT NULL,
    status          VARCHAR(15)  NOT NULL DEFAULT 'ATIVA',
    data_aquisicao  DATE         NOT NULL,
    CONSTRAINT ck_impressora_tecnologia CHECK (tecnologia IN ('FDM','SLA')),
    CONSTRAINT ck_impressora_status     CHECK (status IN ('ATIVA','MANUTENCAO','INATIVA'))
);

-- Tabela PRODUTO
-- Objetivo: catálogo de peças que a oficina vende. Cada produto referencia
-- o material usado e registra peso, tempo de impressão e preço de venda,
-- dados essenciais para precificação, margem e planejamento da produção.

CREATE TABLE produto (
    id_produto           SERIAL        PRIMARY KEY,
    nome                 VARCHAR(100)  NOT NULL UNIQUE,
    categoria            VARCHAR(40)   NOT NULL,
    id_material          INTEGER       NOT NULL,
    peso_g               NUMERIC(8,2)  NOT NULL,
    tempo_impressao_min  INTEGER       NOT NULL,
    preco_venda          NUMERIC(10,2) NOT NULL,
    CONSTRAINT fk_produto_material FOREIGN KEY (id_material) REFERENCES material (id_material),
    CONSTRAINT ck_produto_peso     CHECK (peso_g > 0),
    CONSTRAINT ck_produto_tempo    CHECK (tempo_impressao_min > 0),
    CONSTRAINT ck_produto_preco    CHECK (preco_venda > 0)
);

-- Tabela PEDIDO
-- Objetivo: registrar a compra feita por um cliente (cabeçalho do pedido):
-- data, situação no fluxo (aberto até entregue/cancelado), forma de
-- pagamento e frete. Os produtos comprados ficam na tabela ITEM_PEDIDO.

CREATE TABLE pedido (
    id_pedido        SERIAL        PRIMARY KEY,
    id_cliente       INTEGER       NOT NULL,
    data_pedido      DATE          NOT NULL DEFAULT CURRENT_DATE,
    status           VARCHAR(15)   NOT NULL DEFAULT 'ABERTO',
    forma_pagamento  VARCHAR(10)   NOT NULL,
    valor_frete      NUMERIC(8,2)  NOT NULL DEFAULT 0,
    CONSTRAINT fk_pedido_cliente   FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente),
    CONSTRAINT ck_pedido_status    CHECK (status IN ('ABERTO','EM_PRODUCAO','ENVIADO','ENTREGUE','CANCELADO')),
    CONSTRAINT ck_pedido_pagamento CHECK (forma_pagamento IN ('PIX','CARTAO','BOLETO')),
    CONSTRAINT ck_pedido_frete     CHECK (valor_frete >= 0)
);

-- Tabela ITEM_PEDIDO
-- Objetivo: detalhar quais produtos e quantidades compõem cada pedido.
-- Resolve o relacionamento N:M entre PEDIDO e PRODUTO e guarda o preço
-- unitário praticado na data da venda (histórico, mesmo que o preço do
-- catálogo mude depois).

CREATE TABLE item_pedido (
    id_item         SERIAL        PRIMARY KEY,
    id_pedido       INTEGER       NOT NULL,
    id_produto      INTEGER       NOT NULL,
    quantidade      INTEGER       NOT NULL,
    preco_unitario  NUMERIC(10,2) NOT NULL,
    CONSTRAINT fk_item_pedido  FOREIGN KEY (id_pedido)  REFERENCES pedido (id_pedido) ON DELETE CASCADE,
    CONSTRAINT fk_item_produto FOREIGN KEY (id_produto) REFERENCES produto (id_produto),
    CONSTRAINT uq_item_pedido_produto UNIQUE (id_pedido, id_produto),
    CONSTRAINT ck_item_quantidade CHECK (quantidade > 0),
    CONSTRAINT ck_item_preco      CHECK (preco_unitario > 0)
);

-- Tabela PRODUCAO
-- Objetivo: controlar o chão de fábrica. Cada linha é uma ordem de
-- impressão de um item do pedido em uma impressora específica, com início,
-- fim e situação (fila, imprimindo, concluída ou falha). Permite medir
-- horas de uso por máquina, taxa de falhas e acompanhar prazos.

CREATE TABLE producao (
    id_producao    SERIAL       PRIMARY KEY,
    id_item        INTEGER      NOT NULL,
    id_impressora  INTEGER      NOT NULL,
    data_inicio    TIMESTAMP,
    data_fim       TIMESTAMP,
    status         VARCHAR(12)  NOT NULL DEFAULT 'FILA',
    CONSTRAINT fk_producao_item       FOREIGN KEY (id_item)       REFERENCES item_pedido (id_item),
    CONSTRAINT fk_producao_impressora FOREIGN KEY (id_impressora) REFERENCES impressora (id_impressora),
    CONSTRAINT ck_producao_status     CHECK (status IN ('FILA','IMPRIMINDO','CONCLUIDA','FALHA')),
    CONSTRAINT ck_producao_datas      CHECK (data_fim IS NULL OR (data_inicio IS NOT NULL AND data_fim >= data_inicio))
);

-- Índices nas chaves estrangeiras mais consultadas
CREATE INDEX idx_pedido_cliente   ON pedido (id_cliente);
CREATE INDEX idx_item_pedido      ON item_pedido (id_pedido);
CREATE INDEX idx_producao_item    ON producao (id_item);


-- 2. MASSA DE DADOS (INSERT)


INSERT INTO cliente (nome, email, telefone, cidade, uf, data_cadastro) VALUES
('Mariana Souza',   'mariana.souza@email.com',   '(16) 99811-2201', 'Ribeirão Preto',  'SP', '2026-08-10'),
('Carlos Lima',     'carlos.lima@email.com',     '(19) 99722-3310', 'Campinas',        'SP', '2026-08-12'),
('Fernanda Alves',  'fernanda.alves@email.com',  '(31) 99633-4421', 'Belo Horizonte',  'MG', '2026-08-15'),
('Rafael Costa',    'rafael.costa@email.com',    '(41) 99544-5532', 'Curitiba',        'PR', '2026-08-20'),
('Juliana Prado',   'juliana.prado@email.com',   '(34) 99455-6643', 'Uberaba',         'MG', '2026-08-28'),
('Bruno Martins',   'bruno.martins@email.com',   '(62) 99366-7754', 'Goiânia',         'GO', '2026-09-03'),
('Patrícia Nunes',  'patricia.nunes@email.com',  '(71) 99277-8865', 'Salvador',        'BA', '2026-09-10'),
('Diego Ferreira',  'diego.ferreira@email.com',  '(51) 99188-9976', 'Porto Alegre',    'RS', '2026-09-18'),
('Aline Rocha',     'aline.rocha@email.com',     '(21) 99099-1087', 'Rio de Janeiro',  'RJ', '2026-10-02'),
('Thiago Barbosa',  'thiago.barbosa@email.com',  '(11) 98910-2198', 'São Paulo',       'SP', '2026-10-20');

INSERT INTO material (tipo, cor, marca, preco_kg, estoque_g) VALUES
('PLA',    'Preto',        '3D Lab',  89.90, 3500),
('PLA',    'Branco',       '3D Lab',  89.90, 2800),
('PLA',    'Vermelho',     'Voolt3D', 94.90, 1200),
('PETG',   'Transparente', 'Voolt3D', 109.90, 1800),
('PETG',   'Azul',         'Voolt3D', 109.90,  900),
('ABS',    'Cinza',        '3D Lab',  99.90, 2200),
('TPU',    'Preto',        'Creality', 149.90, 600),
('RESINA', 'Cinza',        'Elegoo',  179.90, 1500);

INSERT INTO impressora (modelo, tecnologia, volume_max_mm, status, data_aquisicao) VALUES
('Creality Ender-3 V3', 'FDM', '220x220x250', 'ATIVA',      '2024-03-15'),
('Bambu Lab A1',        'FDM', '256x256x256', 'ATIVA',      '2024-08-10'),
('Prusa MK4',           'FDM', '250x210x220', 'ATIVA',      '2025-01-20'),
('Anycubic Kobra 2',    'FDM', '220x220x250', 'MANUTENCAO', '2023-11-05'),
('Elegoo Mars 4',       'SLA', '129x80x150',  'ATIVA',      '2025-04-12'),
('Creality K1',         'FDM', '220x220x250', 'ATIVA',      '2025-06-30');

INSERT INTO produto (nome, categoria, id_material, peso_g, tempo_impressao_min, preco_venda) VALUES
('Suporte de Celular Articulado',     'Utilidades',    1,  45, 180, 29.90),
('Vaso Geométrico Low Poly',          'Decoração',     2, 120, 420, 49.90),
('Organizador de Mesa Modular',       'Organização',   1, 210, 600, 69.90),
('Chaveiro Personalizado',            'Brindes',       3,   8,  30, 12.90),
('Case para Raspberry Pi 4',          'Eletrônicos',   6,  95, 300, 54.90),
('Luminária Lithophane',              'Decoração',     2, 160, 540, 89.90),
('Miniatura RPG Dragão',              'Miniaturas',    8,  35, 240, 59.90),
('Capa Protetora de Controle',        'Acessórios',    7,  60, 270, 39.90),
('Suporte de Headset',                'Utilidades',    5, 130, 390, 44.90),
('Engrenagem Sobressalente',          'Peças Técnicas',4,  25,  90, 24.90);


INSERT INTO pedido (id_cliente, data_pedido, status, forma_pagamento, valor_frete) VALUES
(1,  '2026-09-02', 'ENTREGUE',    'PIX',    15.00),
(2,  '2026-09-05', 'ENTREGUE',    'CARTAO', 18.50),
(3,  '2026-09-12', 'ENTREGUE',    'PIX',    22.00),
(4,  '2026-09-20', 'ENVIADO',     'CARTAO', 20.00),
(5,  '2026-10-01', 'ENTREGUE',    'BOLETO', 17.00),
(1,  '2026-10-08', 'EM_PRODUCAO', 'PIX',    15.00),
(6,  '2026-10-15', 'EM_PRODUCAO', 'CARTAO', 19.00),
(7,  '2026-10-22', 'ABERTO',      'PIX',    25.00),
(8,  '2026-10-25', 'CANCELADO',   'BOLETO', 24.00),
(10, '2026-10-30', 'ABERTO',      'CARTAO', 12.00);


INSERT INTO item_pedido (id_pedido, id_produto, quantidade, preco_unitario) VALUES
(1,  1,  2, 29.90),
(1,  4,  5, 12.90),
(2,  3,  1, 69.90),
(3,  6,  1, 89.90),
(3,  2,  2, 49.90),
(4,  5,  1, 54.90),
(4,  9,  1, 44.90),
(5,  7,  3, 59.90),
(6,  8,  2, 39.90),
(6,  1,  1, 29.90),
(7,  2,  1, 49.90),
(7, 10,  4, 24.90),
(8,  6,  1, 89.90),
(9,  3,  2, 69.90),
(10, 4, 20, 12.90);

INSERT INTO producao (id_item, id_impressora, data_inicio, data_fim, status) VALUES
(1,  1, '2026-09-03 08:00', '2026-09-03 14:00', 'CONCLUIDA'),
(2,  2, '2026-09-03 09:00', '2026-09-03 11:30', 'CONCLUIDA'),
(3,  3, '2026-09-06 08:30', '2026-09-06 18:30', 'CONCLUIDA'),
(4,  2, '2026-09-13 07:00', '2026-09-13 16:00', 'CONCLUIDA'),
(5,  1, '2026-09-13 09:00', '2026-09-13 23:00', 'CONCLUIDA'),
(7,  1, '2026-09-21 12:00', '2026-09-21 13:10', 'FALHA'),
(6,  3, '2026-09-21 10:00', '2026-09-21 15:00', 'CONCLUIDA'),
(8,  5, '2026-10-02 08:00', '2026-10-02 20:00', 'CONCLUIDA'),
(9,  6, '2026-10-09 08:00', NULL,                'IMPRIMINDO'),
(11, 2, '2026-10-16 09:00', NULL,                'IMPRIMINDO'),
(12, 3, NULL,               NULL,                'FILA');

-- 3. CONSULTAS (SELECT)

-- Q1. JOIN + GROUP BY: valor total de cada pedido (itens + frete), sem cancelados

SELECT p.id_pedido,
       c.nome                                         AS cliente,
       p.data_pedido,
       p.status,
       SUM(i.quantidade * i.preco_unitario)           AS subtotal,
       p.valor_frete,
       SUM(i.quantidade * i.preco_unitario) + p.valor_frete AS total
FROM pedido p
JOIN cliente c      ON c.id_cliente = p.id_cliente
JOIN item_pedido i  ON i.id_pedido  = p.id_pedido
WHERE p.status <> 'CANCELADO'
GROUP BY p.id_pedido, c.nome, p.data_pedido, p.status, p.valor_frete
ORDER BY p.id_pedido;

-- Q2. JOIN + GROUP BY: faturamento por categoria de produto

SELECT pr.categoria,
       SUM(i.quantidade)                    AS unidades_vendidas,
       SUM(i.quantidade * i.preco_unitario) AS faturamento
FROM item_pedido i
JOIN produto pr ON pr.id_produto = i.id_produto
JOIN pedido  pe ON pe.id_pedido  = i.id_pedido
WHERE pe.status <> 'CANCELADO'
GROUP BY pr.categoria
ORDER BY faturamento DESC;

-- Q3. GROUP BY + HAVING: clientes que gastaram mais de R$ 100 em produtos

SELECT c.nome,
       c.cidade,
       COUNT(DISTINCT p.id_pedido)           AS qtd_pedidos,
       SUM(i.quantidade * i.preco_unitario)  AS total_gasto
FROM cliente c
JOIN pedido p      ON p.id_cliente = c.id_cliente
JOIN item_pedido i ON i.id_pedido  = p.id_pedido
WHERE p.status <> 'CANCELADO'
GROUP BY c.id_cliente, c.nome, c.cidade
HAVING SUM(i.quantidade * i.preco_unitario) > 100
ORDER BY total_gasto DESC;

-- Q4. LEFT JOIN: clientes cadastrados que ainda não fizeram nenhum pedido

SELECT c.id_cliente, c.nome, c.email, c.data_cadastro
FROM cliente c
LEFT JOIN pedido p ON p.id_cliente = c.id_cliente
WHERE p.id_pedido IS NULL;

-- Q5. JOIN + filtros: produtos em PLA ou PETG com preço de venda a partir de R$ 40

SELECT pr.nome, pr.categoria, m.tipo, m.cor, pr.preco_venda
FROM produto pr
JOIN material m ON m.id_material = pr.id_material
WHERE m.tipo IN ('PLA','PETG')
  AND pr.preco_venda >= 40
ORDER BY pr.preco_venda DESC;

-- Q6. JOIN + cálculo: margem bruta estimada por produto (preço - custo do material)

SELECT pr.nome,
       pr.preco_venda,
       ROUND((pr.peso_g / 1000 * m.preco_kg)::numeric, 2)                  AS custo_material,
       ROUND((pr.preco_venda - pr.peso_g / 1000 * m.preco_kg)::numeric, 2) AS margem_bruta
FROM produto pr
JOIN material m ON m.id_material = pr.id_material
ORDER BY margem_bruta DESC;

-- Q7. JOIN + GROUP BY: horas de impressão concluídas por impressora

SELECT im.modelo,
       COUNT(*) AS impressoes_concluidas,
       ROUND((SUM(EXTRACT(EPOCH FROM (pd.data_fim - pd.data_inicio))) / 3600)::numeric, 1) AS horas_impressas
FROM producao pd
JOIN impressora im ON im.id_impressora = pd.id_impressora
WHERE pd.status = 'CONCLUIDA'
GROUP BY im.modelo
ORDER BY horas_impressas DESC;

-- Q8. GROUP BY com FILTER: taxa de falha por impressora

SELECT im.modelo,
       COUNT(*)                                   AS total_ordens,
       COUNT(*) FILTER (WHERE pd.status = 'FALHA') AS falhas,
       ROUND(100.0 * COUNT(*) FILTER (WHERE pd.status = 'FALHA') / COUNT(*), 1) AS pct_falha
FROM impressora im
JOIN producao pd ON pd.id_impressora = im.id_impressora
GROUP BY im.modelo
ORDER BY pct_falha DESC, im.modelo;

-- Q9. Filtro condicional + JOIN: pedidos em andamento (abertos ou em produção) com dados do cliente

SELECT p.id_pedido, c.nome, c.cidade, c.uf, p.status, p.data_pedido
FROM pedido p
JOIN cliente c ON c.id_cliente = p.id_cliente
WHERE p.status IN ('ABERTO','EM_PRODUCAO')
ORDER BY p.data_pedido;

-- Q10. Filtro + ordenação: materiais com estoque baixo (menos de 1.500 g)

SELECT tipo, cor, marca, estoque_g
FROM material
WHERE estoque_g < 1500
ORDER BY estoque_g;

-- Q11. Subconsulta + JOIN: produtos mais vendidos que superam a média de unidades vendidas

SELECT pr.nome, SUM(i.quantidade) AS unidades
FROM item_pedido i
JOIN produto pr ON pr.id_produto = i.id_produto
GROUP BY pr.id_produto, pr.nome
HAVING SUM(i.quantidade) > (SELECT AVG(qtd) FROM (SELECT SUM(quantidade) AS qtd FROM item_pedido GROUP BY id_produto) t)
ORDER BY unidades DESC;




