use classicmodels;
create table auditoria( 
	datamodificacao datetime,
	historico text
);
DELIMITER $


create trigger trg_alterar_quantidade_produto after update on products
for each row
begin
insert into auditoria values (now(), concat('Foi altearado a quantidade do produto ', old.productCode,' de :',old.quantityInStock,' para o novo: ',new.quantityInStock));
end$
create trigger trg_alterar_vendedor_cliente after update on customers
for each row
begin
insert into auditoria values (now(), concat('Foi altearado o número do vendedor do customer ',old.customernumber," de: ", old.SALESREP_EMPLOYEENUMBER,' para o novo: ',new.SALESREP_EMPLOYEENUMBER));
end$
create trigger trg_inserir_order after insert on orders
for each row
begin
insert into auditoria values (now(), concat("Foi incluido na tabela o o order: ", new.orderNumber));
end$
create trigger trg_inserir_orderDetails after insert on orderdetails
for each row
begin
insert into auditoria values (now(), concat("Foi incluido na tabela o orderdetails: ", new.orderNumber));
end$

CREATE PROCEDURE GERAR_ITEM_PEDIDO (IN PARAM_CODIGOPRODUTO VARCHAR(10), IN PARAM_QUANTIDADE INT, IN PARAM_PRECO DECIMAL(10,2), IN PARAM_NUMEROPEDIDO INT, IN PARAM_ORDERLINEBNUMBER INT, OUT ERRO VARCHAR(100))
inicio: BEGIN 
    DECLARE PRODUTO_EXISTENTE INT;
    DECLARE QUANTIDADE_ESTOQUE INT;

    -- Verifica se o produto existe e obter a quantidade em estoque
    SELECT COUNT(*), IFNULL(QUANTITYINSTOCK, 0) INTO PRODUTO_EXISTENTE, QUANTIDADE_ESTOQUE
    FROM PRODUCTS 
    WHERE PRODUCTCODE = PARAM_CODIGOPRODUTO;

    -- Verifica se o produto foi encontrado
    IF PRODUTO_EXISTENTE = 0 THEN
        SET ERRO = 'Produto inválido';
        LEAVE inicio;
    END IF;

    -- Verifica se a quantidade em estoque é suficiente
    IF QUANTIDADE_ESTOQUE < PARAM_QUANTIDADE THEN
        SET ERRO = CONCAT('Quantidade do produto ', PARAM_CODIGOPRODUTO, ' inválida');
        LEAVE inicio;
    END IF;

    -- Inseri o item no pedido
    INSERT INTO ORDERDETAILS 
        VALUES (PARAM_NUMEROPEDIDO, PARAM_CODIGOPRODUTO, PARAM_QUANTIDADE, PARAM_PRECO, PARAM_ORDERLINEBNUMBER);
    
    -- Atualizar quantidade em estoque
    UPDATE PRODUCTS 
    SET QUANTITYINSTOCK = QUANTITYINSTOCK - PARAM_QUANTIDADE 
    WHERE PRODUCTCODE = PARAM_CODIGOPRODUTO;
    
    SET ERRO = '';
END$

CREATE PROCEDURE GERAR_PEDIDO (
    IN PARAM_CLIENTE INT,
    IN PARAM_VENDEDOR INT,
    OUT RESULTADO VARCHAR(200)
)
BEGIN
    DECLARE VAR_EXISTECLIENTE INT DEFAULT 0;
    DECLARE VAR_EXISTEVENDEDOR INT DEFAULT 0;
    DECLARE VAR_NUMEROPEDIDO INT DEFAULT 0;
    DECLARE CONTADOR INT DEFAULT 0;
    DECLARE ERRO VARCHAR(100);

    -- Declaração do cursor
    DECLARE cur CURSOR FOR
        SELECT CODIGOPRODUTO, QUANTIDADE, PRECO
        FROM CARRINHO
        WHERE CODIGOCLIENTE = PARAM_CLIENTE;

    -- Declaração das variáveis do cursor
    DECLARE CONTADOR_WHILE INT DEFAULT 0;
    DECLARE VAR_CODIGOPRODUTO VARCHAR(10);
    DECLARE VAR_QUANTIDADE INT;
    DECLARE VAR_PRECO DECIMAL(10,2);

    -- Declaração do handler para quando não houver mais dados
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET CONTADOR_WHILE = 1;

    -- Inicia transação
    START TRANSACTION;

    -- Obtem o próximo número do pedido
    SELECT IFNULL(MAX(ORDERNUMBER), 0) + 1 INTO VAR_NUMEROPEDIDO FROM ORDERS;

    -- Verifica a existência do cliente
    SELECT COUNT(*) INTO VAR_EXISTECLIENTE
    FROM CUSTOMERS
    WHERE CUSTOMERNUMBER = PARAM_CLIENTE;

    IF VAR_EXISTECLIENTE = 0 THEN
        SET RESULTADO = 'CLIENTE NÃO ENCONTRADO NA BASE DE DADOS';
        ROLLBACK;
        LEAVE inicio;
    END IF;

    -- Verifica a existência do vendedor
    SELECT COUNT(*) INTO VAR_EXISTEVENDEDOR
    FROM EMPLOYEES
    WHERE EMPLOYEENUMBER = PARAM_VENDEDOR;

    IF VAR_EXISTEVENDEDOR = 0 THEN
        SET RESULTADO = 'VENDEDOR NÃO ENCONTRADO NA BASE DE DADOS';
        ROLLBACK;
        LEAVE inicio;
    END IF;

    -- Verifica se o carrinho está vazio
    SELECT COUNT(*) INTO CONTADOR
    FROM CARRINHO
    WHERE CODIGOCLIENTE = PARAM_CLIENTE;

    IF CONTADOR = 0 THEN
        SET RESULTADO = 'O CARRINHO ESTÁ VAZIO';
        ROLLBACK;
        LEAVE inicio;
    END IF;

    -- Verifica o limite de crédito do cliente
    IF (SELECT CREDITLIMIT FROM CUSTOMERS WHERE CUSTOMERNUMBER = PARAM_CLIENTE) < 0 THEN
        SET RESULTADO = 'O CLIENTE NÃO POSSUI LIMITE DE CRÉDITO';
        ROLLBACK;
        LEAVE inicio;
    END IF;

    -- Inseri o pedido
    INSERT INTO ORDERS (ORDERNUMBER, ORDERDATE, REQUIREDDATE, SHIPPEDDATE, STATUS, COMMENTS, CUSTOMERNUMBER)
    VALUES (VAR_NUMEROPEDIDO, CURDATE(), CURDATE() + INTERVAL 7 DAY, NULL, 'processing', '', PARAM_CLIENTE);

    -- Abre o cursor
    OPEN cur;

    -- Inicia o loop do cursor
    read_loop: LOOP
        FETCH cur INTO VAR_CODIGOPRODUTO, VAR_QUANTIDADE, VAR_PRECO;

        -- Verifica se não há mais registros
        IF CONTADOR_WHILE THEN
            LEAVE read_loop;
        END IF;

        -- Gera item do pedido
        CALL GERAR_ITEM_PEDIDO(VAR_CODIGOPRODUTO, VAR_QUANTIDADE, VAR_PRECO, VAR_NUMEROPEDIDO, CONTADOR_WHILE + 1, ERRO);

        -- Verifica se houve erro
        IF ERRO != '' THEN
            ROLLBACK;
            SET RESULTADO = ERRO;
            CLOSE cur;
            LEAVE inicio;
        END IF;

        SET CONTADOR_WHILE = CONTADOR_WHILE + 1;
    END LOOP;

    -- Fecha o cursor
    CLOSE cur;

    -- Atualiza vendedor
    UPDATE CUSTOMERS SET SALESREP_EMPLOYEENUMBER = PARAM_VENDEDOR WHERE CUSTOMERNUMBER = PARAM_CLIENTE;

    -- Confirma a transação
    COMMIT;

    SET RESULTADO = CONCAT('Pedido gerado: ', VAR_NUMEROPEDIDO);

    -- Limpa o carrinho
    DELETE FROM CARRINHO WHERE CODIGOCLIENTE = PARAM_CLIENTE;

END$
DELIMITER ;

-- Testa o procedimento
INSERT INTO CARRINHO VALUES (103, 'a', 10, 10);
CALL GERAR_PEDIDO(103, 1002, @resultado);

-- Cria tabela para armazenar resultados
CREATE TABLE resultado (
    id VARCHAR(100)
);

-- Inseri e verificar o resultado
INSERT INTO resultado VALUES (@resultado);
SELECT * FROM resultado;
SELECT * FROM CARRINHO;

delimiter ;






