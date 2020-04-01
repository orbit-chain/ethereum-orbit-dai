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
    string public constant version = "0401";

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

    function muldiv(uint a, uint b, uint c) private pure returns (uint) {
        uint safe = 1 << (256 - 32);  // 2.696e67
        uint mask = (1 << 32) - 1;

        require(c != 0 && c < safe);

        if (b == 0) return 0;
        if (a < b) (a, b) = (b, a);
        
        uint p = a / c;
        uint r = a % c;

        uint res = 0;

        while (true) {  // most 8 times
            uint v = b & mask;
            res = add(res, add(mul(p, v), r * v / c));

            b >>= 32;
            if (b == 0) break;

            require(p < safe);

            p <<= 32;
            r <<= 32;

            p = add(p, r / c);
            r %= c;
        }

        return res;
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
    function chi() private returns (uint) {
        return now > Pot.rho() ? Pot.drip() : Pot.chi();
    }

    function joinDai(uint dai) private {
        require(Dai.transferFrom(msg.sender, address(this), dai));
        Join.join(address(this), dai);

        uint vat = Vat.dai(address(this));
        Pot.join(div(vat, chi()));
    }

    function exitDai(address to, uint dai) private {
        uint vat = Vat.dai(address(this));
        uint req = mul(dai, ONE);

        if (req > vat) {
            uint pot = ceil(req - vat, chi());
            Pot.exit(pot);
        }

        Join.exit(to, dai);
    }

    function mintODai(address to, uint dai) private returns (uint) {
        uint wad = dai;

        if (ODai.totalSupply() != 0) {
            uint pie = Pot.pie(address(this));
            uint vat = Vat.dai(address(this));

            // 기존 rad
            uint rad = sub(add(mul(pie, chi()), vat), mul(EDai.totalSupply(), ONE));

            // rad : supply = dai * ONE : wad
            wad = muldiv(ODai.totalSupply(), mul(dai, ONE), rad);
        }

        joinDai(dai);
        ODai.mint(to, wad);
        return wad;
    }

    function depositEDai(address to, uint dai, address extraToAddr) public notPaused {
        require(dai > 0);

        joinDai(dai);

        EDai.mint(address(this), dai);
        Reserve.depositToken(address(EDai), to, dai, extraToAddr);
    }

    function depositODai(address to, uint dai, address extraToAddr) public notPaused {
        require(dai > 0);

        uint wad = mintODai(address(this), dai);
        Reserve.depositToken(address(ODai), to, wad, extraToAddr);
    }

    function swapFromEDai(address from, address to, uint dai) private {
        EDai.burn(from, dai);
        exitDai(to, dai);
    }

    function swapFromODai(address from, address to, uint wad) private {
        uint pie = Pot.pie(address(this));
        uint vat = Vat.dai(address(this));

        // 기존 rad
        uint rad = sub(add(mul(pie, chi()), vat), mul(EDai.totalSupply(), ONE));

        // rad : supply = dai * ONE : wad
        uint dai = muldiv(rad, wad, mul(ODai.totalSupply(), ONE));

        ODai.burn(from, wad);
        exitDai(to, dai);
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

        joinDai(dai);
        EDai.mint(msg.sender, dai);
    }

    function swapToODai(uint dai) public notPaused {
        require(dai > 0);

        mintODai(msg.sender, dai);
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

        chi();

        Pot.exit(Pot.pie(address(this)));
        Join.exit(to, Vat.dai(address(this)) / ONE);
    }

    // 새로 생긴 프록시로 자산을 옮긴다.
    function migrateProxy() public notPaused onlyNewProxy {
        state = 2;

        EDai.setProxy(address(NewProxy));
        ODai.setProxy(address(NewProxy));

        chi();

        Pot.exit(Pot.pie(address(this)));
        Vat.move(address(this), address(NewProxy), Vat.dai(address(this)));
    }

    // 프록시를 켠다.
    function startProxy(address oldProxy) public notStarted onlyOwner {
        state = 1;

        if (oldProxy != address(0)) {
            DaiProxy(oldProxy).migrateProxy();

            uint vat = Vat.dai(address(this));
            Pot.join(div(vat, chi()));
        }
    }
}
