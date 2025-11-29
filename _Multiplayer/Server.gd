extends Node
@onready var Spawn: Node = $Spawn

# Configuration
const IP_ADDRESS: String = "localhost"
const PORT: int = 25565
const MAX_CLIENTS: int = 4
var Connected_Clients: Array[int]
var OFFLINE: bool = false

## TODO: Use this to determine authority
var is_active: bool

func Offline() -> void: $Offline.Play()
func Create()  -> void: $Connect.Host(PORT, MAX_CLIENTS)
func Join()    -> void: $Connect.Client(IP_ADDRESS, PORT)
## TODO: Disable Offline on connection
