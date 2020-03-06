pragma solidity ^0.5.0;

contract ReserveLike {
    function depositToken(address, address, uint, address) public;
}

contract WrappedDaiLike {
    function setProxy(address) public;
    function setReserve(address) public;

    uint public totalSupply;
    function approve(address, uint) public returns (bool);

    function mint(address, uint) public;
    function burn(address, uint) public;
}

contract DaiLike {
    function approve(address, uint) public returns (bool);
    function transferFrom(address, address, uint) public returns (bool);
}

contract JoinLike {
    VatLike public vat;
    DaiLike public dai;

    function join(address, uint) public;
    function exit(address, uint) public;
}

contract PotLike {
    mapping(address => uint) public pie;
    uint public chi;

    VatLike public vat;
    uint public rho;

    function drip() public returns (uint);

    function join(uint) public;
    function exit(uint) public;
}

contract VatLike {
    mapping(address => uint) public dai;

    function hope(address) public;
    function move(address, address, uint) public;
}

contract DaiProxy {
    string public constant version = "0306a";

    // --- Owner ---
    address public owner;

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    event SetOwner(address owner);

    function setOwner(address _owner) public onlyOwner {
        owner = _owner;
        emit SetOwner(_owner);
    }

    // --- State ---
    uint public state = 0;  // 0 : 시작 전, 1 : 작동 중, 2 : 사망

    modifier notStarted {
        require(state == 0);
        _;
    }

    modifier notPaused {
        require(state == 1);
        _;
    }

    // --- Math ---
    uint constant ONE = 10 ** 27;

    function add(uint a, uint b) private pure returns (uint) {
        require(a <= uint(-1) - b);
        return a + b;
    }

    function sub(uint a, uint b) private pure returns (uint) {
        require(a >= b);
        return a - b;
    }

    function mul(uint a, uint b) private pure returns (uint) {
        require(b == 0 || a <= uint(-1) / b);
        return a * b;
    }

    function div(uint a, uint b) private pure returns (uint) {
        require(b != 0);
        return a / b;
    }

    function ceil(uint a, uint b) private pure returns (uint) {
        require(b != 0);

        uint r = a / b;
        return a > r * b ? r + 1 : r;
    }

    // --- Contracts & Constructor ---
    DaiLike public Dai;
    JoinLike public Join;
    PotLike public Pot;
    VatLike public Vat;

    ReserveLike public Reserve;

    WrappedDaiLike public EDai;
    WrappedDaiLike public ODai;

    constructor(address dai, address join, address pot, address vat, address eDai, address oDai) public {
        owner = msg.sender;

        Dai = DaiLike(dai);
        Join = JoinLike(join);
        Pot = PotLike(pot);
        Vat = VatLike(vat);

        EDai = WrappedDaiLike(eDai);
        ODai = WrappedDaiLike(oDai);

        require(address(Join.dai()) == dai);
        require(address(Join.vat()) == vat);
        require(address(Pot.vat()) == vat);

        Vat.hope(pot);  // Pot.join
        Vat.hope(join);  // Join.exit

        require(Dai.approve(join, uint(-1)));  // Join.join -> dai.burn
    }

    function setReserve(address reserve) public onlyOwner {
        require(EDai.approve(address(Reserve), 0));
        require(ODai.approve(address(Reserve), 0));

        Reserve = ReserveLike(reserve);

        EDai.setReserve(reserve);
        ODai.setReserve(reserve);

        // approve for Reserve.depositToken
        require(EDai.approve(reserve, uint(-1)));
        require(ODai.approve(reserve, uint(-1)));
    }

    modifier onlyEDai {
        require(msg.sender == address(EDai));
        _;
    }

    modifier onlyODai {
        require(msg.sender == address(ODai));
        _;
    }

    // --- Integration ---
    function grabDai(uint dai) private {
        require(Dai.transferFrom(msg.sender, address(this), dai));
        Join.join(address(this), dai);

        uint vat = Vat.dai(address(this));

        uint chi = now > Pot.rho() ? Pot.drip() : Pot.chi();
        Pot.join(div(vat, chi));
    }

    function fitVat(uint dai) private {
        uint vat = Vat.dai(address(this));

        uint req = mul(dai, ONE);

        if (req > vat) {
            uint chi = now > Pot.rho() ? Pot.drip() : Pot.chi();
            uint pot = ceil(req - vat, chi);

            Pot.exit(pot);
        }
    }

    function depositEDai(address to, uint dai, address extraToAddr) public notPaused {
        require(dai > 0);

        grabDai(dai);

        EDai.mint(address(this), dai);
        Reserve.depositToken(address(EDai), to, dai, extraToAddr);
    }

    function depositODai(address to, uint dai, address extraToAddr) public notPaused {
        require(dai > 0);

        grabDai(dai);

        uint chi = now > Pot.rho() ? Pot.drip() : Pot.chi();
        uint wad = div(mul(dai, ONE), chi);

        ODai.mint(address(this), wad);
        Reserve.depositToken(address(ODai), to, wad, extraToAddr);
    }

    function swapFromEDai(address from, address to, uint dai) private {
        EDai.burn(from, dai);

        fitVat(dai);
        Join.exit(to, dai);
    }

    function swapFromODai(address from, address to, uint wad) private {
        uint chi = now > Pot.rho() ? Pot.drip() : Pot.chi();

        uint pie = Pot.pie(address(this));
        uint vat = Vat.dai(address(this));

        uint remainVat = sub(add(vat, mul(pie, chi)), mul(EDai.totalSupply(), ONE));

        // Avoid integer overflow
        uint one = ONE;

        // always require wad > 0
        uint r = uint(-1) / wad;

        while (remainVat > r) {
            remainVat /= 10;
            one /= 10;
        }

        // burn하면서 totalSupply가 변경되므로 미리 계산
        uint dai = div(mul(remainVat, wad), mul(one, ODai.totalSupply()));

        ODai.burn(from, wad);

        fitVat(dai);
        Join.exit(to, dai);
    }

    function withdrawEDai(address to, uint dai) public onlyEDai notPaused {
        require(dai > 0);
        swapFromEDai(address(Reserve), to, dai);
    }

    function withdrawODai(address to, uint wad) public onlyODai notPaused {
        require(wad > 0);
        swapFromODai(address(Reserve), to, wad);
    }

    function swapToEDai(uint dai) public notPaused {
        require(dai > 0);

        grabDai(dai);

        EDai.mint(msg.sender, dai);
    }

    function swapToODai(uint dai) public notPaused {
        require(dai > 0);

        grabDai(dai);

        uint chi = now > Pot.rho() ? Pot.drip() : Pot.chi();
        uint wad = div(mul(dai, ONE), chi);

        if (wad > 0) ODai.mint(msg.sender, wad);
    }

    function swapFromEDai(uint dai) public notPaused {
        require(dai > 0);
        swapFromEDai(msg.sender, msg.sender, dai);
    }

    function swapFromODai(uint wad) public notPaused {
        require(wad > 0);
        swapFromODai(msg.sender, msg.sender, wad);
    }

    // --- Migration ---
    DaiProxy public NewProxy;

    modifier onlyNewProxy {
        require(msg.sender == address(NewProxy));
        _;
    }

    // 새로운 프록시가 발행되었음을 알린다
    function setNewProxy(address proxy) public onlyOwner {
        NewProxy = DaiProxy(proxy);
    }

    // 프록시의 작동을 완전히 중지하고 돈을 전부 다른 지갑으로 옮긴다
    function killProxy(address to) public notPaused onlyOwner {
        state = 2;

        if (now > Pot.rho()) Pot.drip();

        Pot.exit(Pot.pie(address(this)));
        Join.exit(to, Vat.dai(address(this)) / ONE);
    }

    // 새로 생긴 프록시로 자산을 옮긴다.
    function migrateProxy() public notPaused onlyNewProxy {
        state = 2;

        EDai.setProxy(address(NewProxy));
        ODai.setProxy(address(NewProxy));

        if (now > Pot.rho()) Pot.drip();

        Pot.exit(Pot.pie(address(this)));
        Vat.move(address(this), address(NewProxy), Vat.dai(address(this)));
    }

    // 프록시를 켠다.
    function startProxy(address oldProxy) public notStarted onlyOwner {
        state = 1;

        if (oldProxy != address(0)) {
            DaiProxy(oldProxy).migrateProxy();
            uint vat = Vat.dai(address(this));

            uint chi = now > Pot.rho() ? Pot.drip() : Pot.chi();
            Pot.join(div(vat, chi));
        }
    }
}
