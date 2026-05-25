// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UserContract
 * @dev Contrato auxiliar para almacenar y gestionar de forma aislada los boletos de cada usuario.
 */
contract UserContract {
    address public owner;
    address public mainLottery;
    
    uint256[] private ticketIds;

    constructor(address _owner, address _mainLottery) {
        owner = _owner;
        mainLottery = _mainLottery;
    }

    function addTicket(uint256 _ticketId) external {
        require(msg.sender == mainLottery, "Solo el contrato principal puede agregar boletos");
        ticketIds.push(_ticketId);
    }

    function getTickets() external view returns (uint256[] memory) {
        return ticketIds;
    }
}

/**
 * @title LotteryNFT
 * @dev Representación ERC-721 de los boletos de lotería.
 */
contract LotteryNFT is ERC721, Ownable {
    constructor(address initialOwner) ERC721("BoletoLoteria", "BLT") Ownable(initialOwner) {}

    function safeMint(address to, uint256 tokenId) external onlyOwner {
        _safeMint(to, tokenId);
    }
}

/**
 * @title DecenLottery
 * @dev Contrato principal que integra la economía del token ERC-20 y la lógica de la lotería.
 */
contract DecenLottery is ERC20, Ownable {
    LotteryNFT public nftContract;

    // Configuración del Token ERC-20
    uint256 public constant INITIAL_SUPPLY = 10000 * 10**18;
    uint256 public constant TOKEN_PRICE = 0.001 ether;

    // Configuración de la Lotería (Tokens ERC-20 por cada boleto)
    uint256 public constant TICKET_PRICE = 1 * 10**18; 

    // Comisión del creador de la lotería (porcentaje del premio, ej. 10%)
    uint256 public constant OWNER_FEE_PERCENT = 10;

    // Variables de estado para el seguimiento de boletos
    uint256 public ticketCounter;
    uint256[] public allTickets;
    
    // Variables para registrar al último ganador de la lotería
    address public recentWinner;
    uint256 public winningTicket;

    // Mappings de registro de boletos y usuarios
    mapping(address => address) public userRegistry;
    mapping(uint256 => address) public ticketToBuyer;

    // Eventos
    event UserRegistered(address indexed user, address userContract);
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost);
    event TokensReturned(address indexed user, uint256 amount, uint256 ethReturned);
    event TicketsBought(address indexed buyer, uint256 amountOfTickets, uint256 totalCost);
    // Evento para rastrear la selección de un ganador
    event WinnerSelected(address indexed winner, uint256 ticketId, uint256 prizeAmount);

    constructor() ERC20("TokenLoteria", "TKLO") Ownable(msg.sender) {
        nftContract = new LotteryNFT(address(this));
        _mint(address(this), INITIAL_SUPPLY);
    }

    function _registerUser(address _user) internal {
        if (userRegistry[_user] == address(0)) {
            UserContract newContract = new UserContract(_user, address(this));
            userRegistry[_user] = address(newContract);
            emit UserRegistered(_user, address(newContract));
        }
    }

    function buyTokens(uint256 _amountOfTokens) external payable {
        require(_amountOfTokens > 0, "Debe comprar al menos un token");
        uint256 requiredEth = (_amountOfTokens * TOKEN_PRICE) / 10**18;
        require(msg.value >= requiredEth, "Ether insuficiente para realizar la compra");
        require(balanceOf(address(this)) >= _amountOfTokens, "Reserva de tokens insuficiente");

        _registerUser(msg.sender);
        _transfer(address(this), msg.sender, _amountOfTokens);
        emit TokensPurchased(msg.sender, _amountOfTokens, requiredEth);

        uint256 excess = msg.value - requiredEth;
        if (excess > 0) {
            (bool success, ) = payable(msg.sender).call{value: excess}("");
            require(success, "Fallo al retornar el excedente de Ether");
        }
    }

    function returnTokens(uint256 _amountOfTokens) external {
        require(_amountOfTokens > 0, "La cantidad debe ser mayor a cero");
        require(balanceOf(msg.sender) >= _amountOfTokens, "Saldo de tokens insuficiente");

        uint256 ethToReturn = (_amountOfTokens * TOKEN_PRICE) / 10**18;
        require(address(this).balance >= ethToReturn, "Liquidez de Ether insuficiente en el contrato");

        _transfer(msg.sender, address(this), _amountOfTokens);
        (bool success, ) = payable(msg.sender).call{value: ethToReturn}("");
        require(success, "Fallo al enviar el Ether al usuario");

        emit TokensReturned(msg.sender, _amountOfTokens, ethToReturn);
    }

    function buyTickets(uint256 _ticketCount) external {
        require(_ticketCount > 0, "Debe comprar al menos un boleto");
        uint256 totalCost = _ticketCount * TICKET_PRICE;
        require(balanceOf(msg.sender) >= totalCost, "Saldo de tokens insuficiente para comprar boletos");

        address userContractAddr = userRegistry[msg.sender];
        require(userContractAddr != address(0), "Usuario no registrado en el sistema");

        _transfer(msg.sender, address(this), totalCost);

        for (uint256 i = 0; i < _ticketCount; i++) {
            ticketCounter++;
            uint256 currentTicketId = ticketCounter;

            allTickets.push(currentTicketId);
            ticketToBuyer[currentTicketId] = msg.sender;
            UserContract(userContractAddr).addTicket(currentTicketId);
            nftContract.safeMint(msg.sender, currentTicketId);
        }

        emit TicketsBought(msg.sender, _ticketCount, totalCost);
    }

    function getUserTickets(address _user) external view returns (uint256[] memory) {
        address userContractAddr = userRegistry[_user];
        if (userContractAddr == address(0)) {
            return new uint256[](0);
        }
        return UserContract(userContractAddr).getTickets();
    }

    /**
     * @dev Selecciona al ganador de forma pseudo-aleatoria, distribuye la comisión al creador
     * y el resto del Ether acumulado al ganador. Solo ejecutable por el propietario (owner).
     */
    function generateWinner() external onlyOwner {
        // Validación de existencia de boletos comprados en la ronda
        require(allTickets.length > 0, "No se han comprado boletos todavia");

        // Selección pseudo-aleatoria del boleto ganador utilizando hashing de variables del bloque
        uint256 randomIndex = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    allTickets.length
                )
            )
        ) % allTickets.length;

        uint256 winningTicketId = allTickets[randomIndex];

        // Identificación del usuario comprador asociado al boleto seleccionado
        address winner = ticketToBuyer[winningTicketId];
        require(winner != address(0), "El boleto ganador no tiene comprador");

        // Registro de los datos del ganador en las variables globales del contrato
        recentWinner = winner;
        winningTicket = winningTicketId;

        // Cálculo del premio total (el acumulado neto de Ether en el contrato)
        uint256 totalPrize = address(this).balance;
        require(totalPrize > 0, "No hay fondos de Ether acumulados en el pozo");

        // Cálculo de la comisión del propietario y el premio neto del ganador
        uint256 ownerFee = (totalPrize * OWNER_FEE_PERCENT) / 100;
        uint256 winnerPrize = totalPrize - ownerFee;

        // Distribución de la comisión de administración al propietario del contrato
        if (ownerFee > 0) {
            (bool successOwner, ) = payable(owner()).call{value: ownerFee}("");
            require(successOwner, "Fallo al enviar la comision al administrador");
        }

        // Distribución del premio neto acumulado al ganador
        (bool successWinner, ) = payable(winner).call{value: winnerPrize}("");
        require(successWinner, "Fallo al enviar el premio al ganador");

        // Disparo del evento global con los detalles del sorteo completado
        emit WinnerSelected(winner, winningTicketId, winnerPrize);

        // Opcional: Reinicio de los boletos globales de la ronda
        delete allTickets;
    }
}