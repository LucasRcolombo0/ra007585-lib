-- =====================================================================
-- TRABALHO PRÁTICO 02 — Functions no PostgreSQL (PL/pgSQL)
-- Gestão de Banco de Dados — 2º Bimestre / 2026
-- Aluno: Lucas Reis Colombo  |  RA: 007585
-- Banco: oficina_3d (Oficina de Impressão 3D sob Demanda)
-- =====================================================================
-- CONTEXTO
-- Este script continua o Trabalho 01 e usa as mesmas tabelas (cliente,
-- material, impressora, produto, pedido, item_pedido e producao).
-- Execute primeiro o script_trabalho01.sql e depois este arquivo.
--
-- FUNCTIONS CRIADAS
-- 1. fn_total_pedido        -> calcula o valor total (itens + frete) de um pedido
-- 2. fn_margem_produto      -> classifica a margem de lucro de um produto
-- 3. fn_horas_impressora    -> soma as horas de impressão de uma máquina num período
-- 4. fn_pedidos_cliente     -> lista os pedidos de um cliente com o total de cada um
-- 5. fn_baixar_estoque_pedido -> desconta do estoque os materiais usados em um pedido
-- =====================================================================

-- Coluna de controle usada pela function 5, para não baixar o estoque
-- do mesmo pedido duas vezes.
ALTER TABLE pedido ADD COLUMN IF NOT EXISTS estoque_baixado BOOLEAN NOT NULL DEFAULT FALSE;

-- ---------------------------------------------------------------------
-- FUNCTION 1: fn_total_pedido
-- Objetivo: devolver o valor final de um pedido (soma dos itens + frete).
-- Se o pedido não existir, devolve 0 em vez de erro (tratamento com FOUND).
-- Uso: evita repetir o cálculo do total em várias consultas.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_total_pedido(p_id_pedido INT)
RETURNS NUMERIC(10,2) AS $$
DECLARE
    v_subtotal NUMERIC(10,2);
    v_frete    NUMERIC(8,2);
BEGIN
    SELECT valor_frete INTO v_frete
    FROM pedido
    WHERE id_pedido = p_id_pedido;

    IF NOT FOUND THEN
        RETURN 0.00;
    END IF;

    SELECT COALESCE(SUM(quantidade * preco_unitario), 0)
    INTO v_subtotal
    FROM item_pedido
    WHERE id_pedido = p_id_pedido;

    RETURN v_subtotal + v_frete;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- FUNCTION 2: fn_margem_produto
-- Objetivo: calcular o custo do material de um produto (peso x preço do kg),
-- a margem de lucro em % e classificar a margem como Alta, Média ou Baixa.
-- Regra de negócio: >= 85% Alta | >= 75% Média | abaixo disso Baixa.
-- Retorna um texto pronto para relatório.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_margem_produto(p_id_produto INT)
RETURNS TEXT AS $$
DECLARE
    v_nome   VARCHAR(100);
    v_preco  NUMERIC(10,2);
    v_custo  NUMERIC(10,2);
    v_margem NUMERIC(5,1);
    v_classe TEXT;
BEGIN
    SELECT pr.nome,
           pr.preco_venda,
           ROUND((pr.peso_g / 1000 * m.preco_kg)::numeric, 2)
    INTO v_nome, v_preco, v_custo
    FROM produto pr
    JOIN material m ON m.id_material = pr.id_material
    WHERE pr.id_produto = p_id_produto;

    IF NOT FOUND THEN
        RETURN 'Produto não encontrado!';
    END IF;

    v_margem := ROUND(((v_preco - v_custo) / v_preco * 100)::numeric, 1);

    IF v_margem >= 85 THEN
        v_classe := 'Margem Alta';
    ELSIF v_margem >= 75 THEN
        v_classe := 'Margem Média';
    ELSE
        v_classe := 'Margem Baixa';
    END IF;
    RETURN v_nome || ' - custo R$ ' || v_custo || ' - ' || v_margem || '% - ' || v_classe;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- FUNCTION 3: fn_horas_impressora
-- Objetivo: somar as horas de impressões CONCLUÍDAS de uma impressora em um
-- intervalo de datas. Usa COALESCE para devolver 0 quando não há impressões.
-- Serve para medir a utilização de cada máquina.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_horas_impressora(p_id_impressora INT, p_ini TIMESTAMP, p_fim TIMESTAMP)
RETURNS NUMERIC(8,1) AS $$
DECLARE
    v_horas NUMERIC(8,1);
BEGIN
    SELECT ROUND((SUM(EXTRACT(EPOCH FROM (data_fim - data_inicio))) / 3600)::numeric, 1)
    INTO v_horas
    FROM producao
    WHERE id_impressora = p_id_impressora
      AND status = 'CONCLUIDA'
      AND data_inicio >= p_ini
      AND data_fim <= p_fim;

    RETURN COALESCE(v_horas, 0.0);
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- FUNCTION 4: fn_pedidos_cliente
-- Objetivo: relatório resumido. Devolve uma tabela com todos os pedidos de um
-- cliente (número, data, status e valor total), reaproveitando a function 1.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_pedidos_cliente(p_id_cliente INT)
RETURNS TABLE (id_pedido INT, data_pedido DATE, status VARCHAR(15), total NUMERIC(10,2)) AS $$
BEGIN
    RETURN QUERY
    SELECT p.id_pedido,
           p.data_pedido,
           p.status,
           fn_total_pedido(p.id_pedido)
    FROM pedido p
    WHERE p.id_cliente = p_id_cliente
    ORDER BY p.data_pedido;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- FUNCTION 5: fn_baixar_estoque_pedido
-- Objetivo: rotina de atualização. Percorre os itens de um pedido com um LOOP,
-- calcula quantos gramas de material foram usados (peso do produto x quantidade)
-- e desconta do estoque do material. Depois marca o pedido como baixado.
-- Regras: pedido inexistente, cancelado ou já baixado não é processado, e se o
-- estoque for insuficiente a função cancela tudo com mensagem de erro.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_baixar_estoque_pedido(p_id_pedido INT)
RETURNS VOID AS $$
DECLARE
    reg         RECORD;
    v_status    VARCHAR(15);
    v_baixado   BOOLEAN;
    v_gramas    INTEGER;
    v_estoque   INTEGER;
BEGIN
    SELECT status, estoque_baixado INTO v_status, v_baixado
    FROM pedido
    WHERE id_pedido = p_id_pedido;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pedido % não encontrado', p_id_pedido;
    END IF;
    IF v_status = 'CANCELADO' THEN
        RAISE EXCEPTION 'Pedido % está cancelado e não pode baixar estoque', p_id_pedido;
    END IF;

    IF v_baixado THEN
        RAISE NOTICE 'Pedido % já teve o estoque baixado', p_id_pedido;
        RETURN;
    END IF;

    FOR reg IN (
        SELECT ip.quantidade, pr.nome, pr.peso_g, pr.id_material
        FROM item_pedido ip
        JOIN produto pr ON pr.id_produto = ip.id_produto
        WHERE ip.id_pedido = p_id_pedido
    ) LOOP
        v_gramas := CEIL(reg.peso_g * reg.quantidade);

        SELECT estoque_g INTO v_estoque
        FROM material
        WHERE id_material = reg.id_material;

        IF v_estoque < v_gramas THEN
            RAISE EXCEPTION 'Estoque insuficiente para "%": precisa de % g e há % g', reg.nome, v_gramas, v_estoque;
        END IF;

        UPDATE material
        SET estoque_g = estoque_g - v_gramas
        WHERE id_material = reg.id_material;
    END LOOP;
    UPDATE pedido SET estoque_baixado = TRUE WHERE id_pedido = p_id_pedido;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- EXEMPLOS DE EXECUÇÃO
-- =====================================================================

-- Function 1
SELECT fn_total_pedido(1);
SELECT fn_total_pedido(99);
SELECT id_pedido, status, fn_total_pedido(id_pedido) AS total FROM pedido ORDER BY id_pedido;

-- Function 2
SELECT fn_margem_produto(1);
SELECT fn_margem_produto(99);
SELECT fn_margem_produto(id_produto) FROM produto ORDER BY id_produto;
-- Function 3
SELECT fn_horas_impressora(1, '2026-09-01 00:00', '2026-09-30 23:59');
SELECT modelo, fn_horas_impressora(id_impressora, '2026-09-01 00:00', '2026-10-31 23:59') AS horas
FROM impressora ORDER BY id_impressora;

-- Function 4
SELECT * FROM fn_pedidos_cliente(1);
SELECT * FROM fn_pedidos_cliente(9);

-- Function 5 (confere o estoque antes e depois)
SELECT tipo, cor, estoque_g FROM material ORDER BY id_material;
SELECT fn_baixar_estoque_pedido(6);
SELECT tipo, cor, estoque_g FROM material ORDER BY id_material;
SELECT fn_baixar_estoque_pedido(6);
