# Lotería Descentralizada con Solidity

Este proyecto consiste en el diseño e implementación de un sistema de lotería descentralizada desarrollado en Solidity utilizando el entorno de desarrollo Remix IDE. La arquitectura se compone de tres contratos inteligentes integrados en un único archivo fuente, aprovechando los estándares de seguridad y tokens de **OpenZeppelin**.

El sistema permite a los usuarios interactuar con una economía de token de utilidad ERC-20, adquirir boletos representados mediante tokens no fungibles (NFT) ERC-721, y participar en sorteos administrados de manera automática.

---

## Arquitectura del Sistema

El proyecto implementa un modelo modular de tres contratos que cooperan entre sí en tiempo de ejecución:

1. **`DecenLottery` (Contrato Principal):**
   * Centraliza la lógica de administración, el ciclo económico y el sorteo.
   * Hereda de `ERC20` para actuar como el token interno de utilidad del juego (`TKLO`).
   * Hereda de `Ownable` para restringir funciones administrativas críticas.
   * Actúa como un contrato "fábrica" (*factory contract*) para desplegar contratos auxiliares de forma automática.

2. **`LotteryNFT` (Contrato de Boletos - ERC-721):**
   * Representa los boletos de lotería únicos como NFTs estándar (`BLT`).
   * Delega la propiedad exclusiva de acuñación (`safeMint`) al contrato principal mediante restricciones de acceso (`onlyOwner`), previniendo la emisión fraudulenta de boletos.

3. **`UserContract` (Contrato Auxiliar del Usuario):**
   * Se despliega dinámicamente en la blockchain la primera vez que un usuario compra tokens.
   * Funciona como un almacén de datos aislado para registrar los boletos adquiridos por su propietario.
   * Protege el estado del usuario limitando las llamadas de actualización únicamente al contrato de la lotería principal.

---

## Funcionamiento y Flujo de Trabajo

El flujo completo del juego se divide en cuatro etapas principales:

1. **Adquisición de Tokens (`buyTokens`):** Los usuarios compran tokens ERC-20 enviando Ether al contrato principal bajo una tasa fija establecida en `TOKEN_PRICE = 0.001 ether`. Si es su primera compra, el contrato principal detecta su dirección y despliega automáticamente su respectivo `UserContract`.
2. **Liquidación de Tokens (`returnTokens`):** Los usuarios pueden devolver sus tokens de utilidad acumulados y recuperar su Ether de forma segura bajo la misma tasa de cambio, garantizando la colateralización y liquidez del contrato.
3. **Compra de Boletos (`buyTickets`):** Los usuarios intercambian sus tokens ERC-20 por boletos de lotería (a razón de `1 token` por boleto). El contrato transfiere los tokens a su reserva, incrementa un contador de boletos secuenciales y acuña un NFT único en el contrato ERC-721 asignado al comprador, actualizando simultáneamente el `UserContract` del usuario.
4. **Sorteo del Ganador (`generateWinner`):** Únicamente ejecutable por el creador del juego (`onlyOwner`). El contrato selecciona un boleto ganador, identifica a su propietario, calcula una comisión de administración (definida en un `10%`) para el administrador y envía el `90%` restante del Ether acumulado de manera directa al ganador.

---

## Medidas de Seguridad Clave

* **Patrón Checks-Effects-Interactions (CEI):** Implementado estrictamente en los retiros y devoluciones de valor para prevenir ataques de reentrada (*reentrancy*). El contrato siempre actualiza sus balances internos de tokens y estados antes de realizar llamadas de transferencia externa de Ether nativo.
* **Control de Acceso (`onlyOwner`):** Las funciones administrativas, como la ejecución del sorteo y el minteo de boletos NFT, están estrictamente restringidas para evitar abusos o manipulaciones externas de estado.
* **Aislamiento de Almacenamiento:** El uso de contratos auxiliares por usuario mitiga el crecimiento indefinido de arreglos dinámicos en el contrato principal, optimizando los costos de gas de almacenamiento de datos (*storage write gas*) en la blockchain.

---

## Instrucciones para Pruebas en Remix IDE

Para desplegar y verificar el funcionamiento del contrato en el simulador local de Remix (Remix VM):

1. **Despliegue inicial:**
   * Seleccione el compilador de Solidity `^0.8.20` y compile el archivo sin errores.
   * Use una cuenta de Remix (por ejemplo, `Account 1`) como Administrador y despliegue el contrato `DecenLottery`.

2. **Fase de Compra de Tokens:**
   * Cambie a una cuenta de pruebas (`Account 2`).
   * Configure el campo **Value** en `10 finney` (0.01 ETH) en Remix.
   * Ingrese el parámetro `10000000000000000000` (10 tokens completos) y presione el botón rosa **`buyTokens`**.

3. **Fase de Compra de Boletos:**
   * Con la misma cuenta (`Account 2`), restablezca el campo **Value** a `0`.
   * En la función **`buyTickets`**, ingrese el parámetro `5` (para comprar 5 boletos) y ejecute la transacción. Esto consumirá 5 de sus 10 tokens y acuñará 5 NFTs representativos.

4. **Fase de Verificación de Variables:**
   * Llame a la función `getUserTickets` pasando la dirección de `Account 2`. Retornará con éxito la lista de boletos: `[1, 2, 3, 4, 5]`.
   * Llame a `balanceOf` del usuario para verificar que su balance de tokens ERC-20 haya disminuido a exactamente `5000000000000000000` ($5$ tokens).

5. **Fase de Ejecución del Sorteo:**
   * Cambie el selector de cuentas superior de vuelta al Administrador (`Account 1`).
   * Ejecute la función **`generateWinner`**.
   * Verifique los balances de Ether en Remix: El administrador habrá recibido el $10\%$ del Ether acumulado y el ganador elegido habrá recibido el $90\%$ restante de manera inmediata.
