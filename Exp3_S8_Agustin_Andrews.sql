-- ============================================================================
-- ACTIVIDAD SUMATIVA SEMANA 8
-- "Desarrollando programas PL/SQL en la Base de Datos"
-- Hotel "La Ultima Oportunidad"
-- ============================================================================
-- Asignatura: Programacion de Bases de Datos (PRY2206)
-- Estudiante: Agustín Andrews
-- ============================================================================
-- NOTA: Ejecutar previamente el script "Script_prueba3_FC.sql" para crear
-- y poblar las tablas del modelo de datos.
-- ============================================================================

SET SERVEROUTPUT ON;

-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
--                              C A S O   1
--        TRIGGER DE REGISTRO AUTOMATICO DE CONSUMOS EN TOTAL_CONSUMOS
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

CREATE OR REPLACE TRIGGER tr_consumo_total
AFTER INSERT OR UPDATE OR DELETE ON consumo
FOR EACH ROW
DECLARE
    v_existe NUMBER;
BEGIN
    -- ======================================================================
    -- CASO INSERT: Se agrega el monto del nuevo consumo al total
    -- Si el huesped no existe en TOTAL_CONSUMOS, se crea el registro
    -- Si existe, se actualiza sumando el nuevo monto
    -- ======================================================================
    IF INSERTING THEN
        -- Verificar si el huesped ya tiene registro en TOTAL_CONSUMOS
        SELECT COUNT(*) 
        INTO v_existe 
        FROM total_consumos 
        WHERE id_huesped = :NEW.id_huesped;

        IF v_existe > 0 THEN
            -- Actualizar: sumar el monto del nuevo consumo
            UPDATE total_consumos 
            SET monto_consumos = monto_consumos + :NEW.monto 
            WHERE id_huesped = :NEW.id_huesped;
        ELSE
            -- Insertar: crear registro para este huesped
            INSERT INTO total_consumos VALUES (:NEW.id_huesped, :NEW.monto);
        END IF;

    -- ======================================================================
    -- CASO UPDATE: Se ajusta el total por la diferencia entre
    -- el nuevo monto y el monto anterior
    -- Si aumenta -> se suma la diferencia
    -- Si disminuye -> se resta la diferencia
    -- ======================================================================
    ELSIF UPDATING THEN
        UPDATE total_consumos 
        SET monto_consumos = monto_consumos + (:NEW.monto - :OLD.monto) 
        WHERE id_huesped = :NEW.id_huesped;

    -- ======================================================================
    -- CASO DELETE: Se rebaja el monto del consumo eliminado
    -- del total del huesped
    -- ======================================================================
    ELSIF DELETING THEN
        UPDATE total_consumos 
        SET monto_consumos = monto_consumos - :OLD.monto 
        WHERE id_huesped = :OLD.id_huesped;
    END IF;
END tr_consumo_total;
/

-- ============================================================================
-- BLOQUE ANONIMO DE PRUEBA DEL TRIGGER (CASO 1)
-- Ejecuta las tres operaciones indicadas en el requerimiento:
--   1. INSERT: nuevo consumo para cliente 340006, reserva 1587, monto US$150
--   2. DELETE: eliminar consumo con ID 11473
--   3. UPDATE: actualizar a US$95 el monto del consumo ID 10688
-- ============================================================================
DECLARE
    v_max_id consumo.id_consumo%TYPE;
BEGIN
    -- Obtener el ID siguiente al ultimo ingresado
    SELECT MAX(id_consumo) + 1 INTO v_max_id FROM consumo;
    
    DBMS_OUTPUT.PUT_LINE('=== PRUEBA DEL TRIGGER tr_consumo_total ===');
    DBMS_OUTPUT.PUT_LINE('Nuevo ID de consumo: ' || v_max_id);
    
    -- 1) Insertar nuevo consumo: cliente 340006, reserva 1587, monto US$150
    --    El trigger debe SUMAR 150 al total de consumos del huesped 340006
    INSERT INTO consumo VALUES (v_max_id, 1587, 340006, 150);
    DBMS_OUTPUT.PUT_LINE('INSERT completado: consumo ' || v_max_id || 
                         ' para huesped 340006, monto $150');

    -- 2) Eliminar consumo con ID 11473 (huesped 340004, monto 63)
    --    El trigger debe RESTAR 63 del total de consumos del huesped 340004
    DELETE FROM consumo WHERE id_consumo = 11473;
    DBMS_OUTPUT.PUT_LINE('DELETE completado: consumo 11473 eliminado');

    -- 3) Actualizar a US$95 el monto del consumo ID 10688 (huesped 340008)
    --    Monto anterior: 117, nuevo: 95. Diferencia: -22
    --    El trigger debe RESTAR 22 del total de consumos del huesped 340008
    UPDATE consumo SET monto = 95 WHERE id_consumo = 10688;
    DBMS_OUTPUT.PUT_LINE('UPDATE completado: consumo 10688 actualizado a $95');

    -- Confirmar cambios
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('=== PRUEBA FINALIZADA EXITOSAMENTE ===');
END;
/

-- Verificacion de resultados del trigger
-- Se muestran los consumos y totales de los huespedes afectados
SELECT 'CONSUMO' AS tabla, id_consumo, id_reserva, id_huesped, monto 
FROM consumo 
WHERE id_huesped IN (340003, 340004, 340006, 340008, 340009) 
ORDER BY id_huesped, id_consumo;

SELECT 'TOTAL_CONSUMOS' AS tabla, id_huesped, monto_consumos 
FROM total_consumos 
WHERE id_huesped IN (340003, 340004, 340006, 340008, 340009) 
ORDER BY id_huesped;


-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
--                              C A S O   2
--              PROCESO INTEGRAL DE GESTION DE COBRANZA
-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-- ============================================================================
-- FUNCION 1: FN_AGENCIA
-- Retorna el nombre de la agencia de procedencia del huesped.
-- Si ocurre un error (ej: huesped sin agencia, id_agencia NULL),
-- registra el error en REG_ERRORES y retorna 'NO REGISTRA AGENCIA'.
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_agencia(
    p_id_huesped IN huesped.id_huesped%TYPE
) RETURN VARCHAR2
IS
    -- Variable anclada al tipo de la columna nom_agencia
    v_nom_agencia agencia.nom_agencia%TYPE;
    -- Variable para capturar el mensaje de error (SQLERRM no se puede usar en SQL)
    v_error VARCHAR2(200);
BEGIN
    -- SELECT INTO para obtener la agencia del huesped
    -- Se usa join implicito entre huesped y agencia
    SELECT a.nom_agencia 
    INTO v_nom_agencia
    FROM agencia a, huesped h
    WHERE h.id_huesped = p_id_huesped
    AND h.id_agencia = a.id_agencia;
    
    RETURN v_nom_agencia;

EXCEPTION
    -- Captura de cualquier excepcion (ej: NO_DATA_FOUND si
    -- id_agencia es NULL o no existe en tabla agencia)
    WHEN OTHERS THEN
        -- Capturar SQLERRM en variable
        v_error := SQLERRM;
        -- Registrar error en tabla REG_ERRORES usando secuencia SQ_ERROR
        INSERT INTO reg_errores VALUES (
            sq_error.NEXTVAL,
            'Error en la funcion FN AGENCIA al recuperar la agencia del huesped con id ' || p_id_huesped,
            v_error
        );
        -- Retornar mensaje indicando que no registra agencia
        RETURN 'NO REGISTRA AGENCIA';
END fn_agencia;
/

-- ============================================================================
-- FUNCION 2: FN_CONSUMOS
-- Retorna el monto en dolares de los consumos del huesped desde
-- la tabla TOTAL_CONSUMOS. Si no registra consumos, retorna 0.
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_consumos(
    p_id_huesped IN huesped.id_huesped%TYPE
) RETURN NUMBER
IS
    -- Variable anclada al tipo de monto_consumos
    v_monto total_consumos.monto_consumos%TYPE;
    -- Variable para capturar el mensaje de error 
    v_error VARCHAR2(200);
BEGIN
    -- SELECT para obtener el total de consumos
    SELECT monto_consumos 
    INTO v_monto
    FROM total_consumos
    WHERE id_huesped = p_id_huesped;
    
    RETURN v_monto;

EXCEPTION
    -- Si el huesped no tiene consumos registrados (NO_DATA_FOUND)
    WHEN NO_DATA_FOUND THEN
        -- Capturar SQLERRM en variable
        v_error := SQLERRM;
        -- Registrar el error en REG_ERRORES
        INSERT INTO reg_errores VALUES (
            sq_error.NEXTVAL,
            'Error en la funcion FN CONSUMOS al recuperar los consumos del cliente con Id ' || p_id_huesped,
            v_error
        );
        -- Retornar 0 indicando que no tiene consumos
        RETURN 0;
END fn_consumos;
/


-- ============================================================================
-- PACKAGE PKG_HOTEL
-- ============================================================================
-- CREATE OR REPLACE PACKAGE (Especificacion) y PACKAGE BODY (Cuerpo)
-- Constructores publicos declarados en la especificacion:
--   - Funcion fn_tours: calcula monto en dolares de tours del huesped
--   - Variable v_monto_tours: almacena el monto para uso del procedimiento
-- ============================================================================

-- Especificacion del Package (constructores publicos)
CREATE OR REPLACE PACKAGE pkg_hotel IS
    
    -- Variable publica para almacenar el monto de tours
    -- Permite al procedimiento principal acceder al ultimo monto calculado
    v_monto_tours NUMBER;
    
    -- Funcion publica: determina el monto en dolares que debe pagar
    -- el huesped por los tours tomados. Retorna 0 si no tomo tours.
    FUNCTION fn_tours(
        p_id_huesped IN huesped.id_huesped%TYPE
    ) RETURN NUMBER;

END pkg_hotel;
/

-- Cuerpo del Package (implementacion de constructores)
CREATE OR REPLACE PACKAGE BODY pkg_hotel IS

    -- ========================================================================
    -- Implementacion de fn_tours
    -- Calcula: SUM(valor_tour * num_personas) para todos los tours
    -- del huesped. Si no tomo tours, retorna 0.
    -- ========================================================================
    FUNCTION fn_tours(
        p_id_huesped IN huesped.id_huesped%TYPE
    ) RETURN NUMBER
    IS
        v_total NUMBER := 0;
        
        -- Cursor explicito para recorrer los tours del huesped
        -- Join implicito entre huesped_tour y tour
        CURSOR c_tours IS
            SELECT t.valor_tour, ht.num_personas
            FROM huesped_tour ht, tour t
            WHERE ht.id_tour = t.id_tour
            AND ht.id_huesped = p_id_huesped;
    BEGIN
        -- Procesamiento con FOR reg IN cursor LOOP
        -- Si el huesped no tiene tours, el loop no se ejecuta y v_total = 0
        FOR reg IN c_tours LOOP
            v_total := v_total + (reg.valor_tour * NVL(reg.num_personas, 1));
        END LOOP;
        
        RETURN v_total;
    END fn_tours;

END pkg_hotel;
/


-- ============================================================================
-- PROCEDIMIENTO ALMACENADO PRINCIPAL
-- ============================================================================
-- CREATE OR REPLACE PROCEDURE con parametros formales (IN)
-- Cursor explicito con parametros
-- Bloques anidados para manejo de excepciones individuales
-- Integra las funciones almacenadas independientes y el Package
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_cobro_diario(
    p_fecha       IN DATE,     -- Fecha de salida (checkout) de los huespedes
    p_valor_dolar IN NUMBER    -- Valor de cambio del dolar en pesos chilenos
)
IS
    -- ========================================================================
    -- Selecciona los huespedes cuya fecha de salida coincide con p_fecha.
    -- Fecha de salida = fecha de ingreso + dias de estadia.
    -- ========================================================================
    CURSOR c_huespedes IS
        SELECT h.id_huesped, 
               h.appat_huesped, 
               h.apmat_huesped,
               h.nom_huesped, 
               r.id_reserva, 
               r.estadia
        FROM reserva r, huesped h
        WHERE r.id_huesped = h.id_huesped
        AND r.ingreso + r.estadia = p_fecha;

    -- Variables para calculos en dolares (USD)
    v_alojamiento_usd    NUMBER := 0;  -- Costo de hospedaje + valor por persona
    v_consumos_usd       NUMBER := 0;  -- Consumos del huesped
    v_tours_usd          NUMBER := 0;  -- Costo de tours
    v_subtotal_usd       NUMBER := 0;  -- Monto acumulado
    v_desc_consumos_usd  NUMBER := 0;  -- Descuento por tramo de consumos
    v_desc_agencia_usd   NUMBER := 0;  -- Descuento por agencia (12% Alberti)
    v_total_usd          NUMBER := 0;  -- Total a pagar

    -- Variables auxiliares
    v_nombre             VARCHAR2(60);  -- Nombre completo del huesped
    v_agencia            VARCHAR2(40);  -- Nombre de la agencia
    v_pct_tramo          NUMBER := 0;   -- Porcentaje del tramo de consumos
    v_num_habitaciones   NUMBER := 0;   -- Cantidad de habitaciones (personas)
    v_valor_persona_usd  NUMBER := 0;   -- Valor por persona en USD

BEGIN
    -- ========================================================================
    -- LIMPIEZA DE TABLAS DE SALIDA Y ERRORES
    -- DML - DELETE para asegurar la re-ejecucion del proceso
    -- ========================================================================
    DELETE FROM detalle_diario_huespedes;
    DELETE FROM reg_errores;

    -- ========================================================================
    -- Procesamiento del cursor con FOR reg IN cursor LOOP
    -- Recorre todos los huespedes cuya salida es p_fecha
    -- ========================================================================
    FOR reg IN c_huespedes LOOP
        -- ==================================================================
        -- Bloque anidado para controlar excepciones individuales
        -- Si un huesped genera error, se continua con el siguiente
        -- ==================================================================
        BEGIN
            -- ==============================================================
            -- NOMBRE DEL HUESPED
            -- Funcion INITCAP para formato de nombre propio
            -- ==============================================================
            v_nombre := INITCAP(reg.appat_huesped) || ' ' || 
                        INITCAP(reg.apmat_huesped);

            -- ==============================================================
            -- AGENCIA DEL HUESPED
            -- Uso de funcion almacenada independiente fn_agencia
            -- Si hay error, la funcion registra en REG_ERRORES y retorna
            -- 'NO REGISTRA AGENCIA'
            -- ==============================================================
            v_agencia := fn_agencia(reg.id_huesped);

            -- ==============================================================
            -- ALOJAMIENTO EN USD
            -- Pago por estadia diaria = valor_habitacion + valor_minibar
            -- Alojamiento = SUM(valor_hab + valor_mini) * dias de estadia
            -- Se suman todas las habitaciones de la reserva
            -- ==============================================================
            SELECT NVL(SUM(ha.valor_habitacion + ha.valor_minibar), 0) * reg.estadia
            INTO v_alojamiento_usd
            FROM detalle_reserva dr, habitacion ha
            WHERE dr.id_habitacion = ha.id_habitacion
            AND dr.id_reserva = reg.id_reserva;

            -- ==============================================================
            -- VALOR POR PERSONA
            -- $35.000 CLP por cada persona que se hospeda
            -- Numero de personas = numero de habitaciones reservadas
            -- Se convierte a USD: ROUND(35000 / valor_dolar)
            -- Se incluye en alojamiento (no tiene columna separada)
            -- ==============================================================
            SELECT COUNT(*) 
            INTO v_num_habitaciones
            FROM detalle_reserva
            WHERE id_reserva = reg.id_reserva;

            v_valor_persona_usd := ROUND(35000 / p_valor_dolar) * v_num_habitaciones;
            v_alojamiento_usd := v_alojamiento_usd + v_valor_persona_usd;

            -- ==============================================================
            -- CONSUMOS EN USD
            -- Uso de funcion almacenada independiente fn_consumos
            -- Consulta la tabla TOTAL_CONSUMOS
            -- Si no registra consumos, retorna 0 y guarda error
            -- ==============================================================
            v_consumos_usd := fn_consumos(reg.id_huesped);

            -- ==============================================================
            -- TOURS EN USD
            -- Uso de la funcion del Package pkg_hotel.fn_tours
            -- Calcula SUM(valor_tour * num_personas) por tour
            -- Si no tomo tours, retorna 0
            -- ==============================================================
            v_tours_usd := pkg_hotel.fn_tours(reg.id_huesped);
            -- Almacenar en variable publica del package (optativo)
            pkg_hotel.v_monto_tours := v_tours_usd;

            -- ==============================================================
            -- SUBTOTAL EN USD
            -- Monto acumulado = alojamiento + consumos + tours
            -- (alojamiento ya incluye el valor por persona)
            -- ==============================================================
            v_subtotal_usd := v_alojamiento_usd + v_consumos_usd + v_tours_usd;

            -- ==============================================================
            -- DESCUENTO POR CONSUMOS
            -- Se busca el tramo en tabla TRAMOS_CONSUMOS segun el monto
            -- de consumos en USD. El porcentaje se aplica sobre consumos.
            -- Bloque anidado para manejar NO_DATA_FOUND
            -- ==============================================================
            v_desc_consumos_usd := 0;
            IF v_consumos_usd > 0 THEN
                BEGIN
                    SELECT pct 
                    INTO v_pct_tramo
                    FROM tramos_consumos
                    WHERE v_consumos_usd >= vmin_tramo 
                    AND v_consumos_usd <= vmax_tramo;

                    v_desc_consumos_usd := ROUND(v_consumos_usd * v_pct_tramo);
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        v_desc_consumos_usd := 0;
                END;
            END IF;

            -- ==============================================================
            -- DESCUENTO POR AGENCIA
            -- 12% adicional sobre el monto acumulado (subtotal)
            -- Solo aplica si la agencia es 'VIAJES ALBERTI'
            -- No aplica para otras agencias
            -- ==============================================================
            v_desc_agencia_usd := 0;
            IF UPPER(v_agencia) = 'VIAJES ALBERTI' THEN
                v_desc_agencia_usd := ROUND(v_subtotal_usd * 0.12);
            END IF;

            -- ==============================================================
            -- TOTAL A PAGAR EN USD
            -- Total = subtotal - descuento por consumos - descuento agencia
            -- ==============================================================
            v_total_usd := v_subtotal_usd - v_desc_consumos_usd - v_desc_agencia_usd;

            -- ==============================================================
            -- INSERCION EN DETALLE_DIARIO_HUESPEDES
            -- Todos los valores se convierten a pesos chilenos (CLP)
            -- multiplicando por el valor del dolar parametrico
            -- Los valores ya estan redondeados a enteros en USD,
            -- por lo que al multiplicar por un entero resultan enteros
            -- ==============================================================
            INSERT INTO detalle_diario_huespedes VALUES (
                reg.id_huesped,
                v_nombre,
                v_agencia,
                v_alojamiento_usd * p_valor_dolar,       -- alojamiento en CLP
                v_consumos_usd * p_valor_dolar,           -- consumos en CLP
                v_tours_usd * p_valor_dolar,              -- tours en CLP
                v_subtotal_usd * p_valor_dolar,           -- subtotal en CLP
                v_desc_consumos_usd * p_valor_dolar,      -- desc consumos en CLP
                v_desc_agencia_usd * p_valor_dolar,       -- desc agencia en CLP
                v_total_usd * p_valor_dolar               -- total en CLP
            );

        EXCEPTION
            -- Si hay error con un huesped individual, se continua
            -- con el siguiente sin interrumpir el proceso
            WHEN OTHERS THEN
                NULL;
        END;
    END LOOP;

    -- COMMIT para confirmar la transaccion
    COMMIT;
END sp_cobro_diario;
/


-- ============================================================================
-- EJECUCION DEL PROCEDIMIENTO PRINCIPAL (CASO 2)
-- Parametros:
--   - Fecha de salida: 18/08/2021
--   - Valor del dolar: $915 CLP
-- ============================================================================
ALTER SESSION DISABLE PARALLEL DML;
BEGIN
    sp_cobro_diario(
        p_fecha       => TO_DATE('18/08/2021', 'DD/MM/YYYY'),
        p_valor_dolar => 915
    );
    DBMS_OUTPUT.PUT_LINE('Proceso de cobro diario ejecutado correctamente.');
END;
/

-- ============================================================================
-- VERIFICACION DE RESULTADOS DEL CASO 2
-- ============================================================================

-- Contenido de la tabla DETALLE_DIARIO_HUESPEDES
SELECT id_huesped, nombre, agencia, alojamiento, consumos, tours,
       subtotal_pago, descuento_consumos, descuentos_agencia, total
FROM detalle_diario_huespedes 
ORDER BY id_huesped;

-- Contenido de la tabla REG_ERRORES
SELECT id_error, nomsubprograma, msg_error 
FROM reg_errores 
ORDER BY id_error;
