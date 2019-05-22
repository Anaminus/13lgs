--[[ Template

Returns a generated input that produces a clean-slate place file.

]]

return rbxmk.input{"generate://Instance", [[
	Workspace{IsService(true); Reference("Workspace");
		Name             : string = "Workspace";
		StreamingEnabled : bool   = false;
	};
	Players{IsService(true); Reference("Players");
		Name               : string = "Players";
		CharacterAutoLoads : bool   = false;
	};
	ReplicatedFirst{IsService(true); Reference("ReplicatedFirst");
		Name : string = "ReplicatedFirst";
	};
	ReplicatedStorage{IsService(true); Reference("ReplicatedStorage");
		Name : string = "ReplicatedStorage";
	};
	ServerScriptService{IsService(true); Reference("ServerScriptService");
		Name              : string = "ServerScriptService";
		LoadStringEnabled : bool   = false;
	};
	ServerStorage{IsService(true); Reference("ServerStorage");
		Name : string = "ServerStorage";
	};
	StarterGui{IsService(true); Reference("StarterGui");
		Name : string = "StarterGui";
	};
	StarterPack{IsService(true); Reference("StarterPack");
		Name : string = "StarterPack";
	};
	SoundService{IsService(true); Reference("SoundService");
		Name : string = "SoundService";
	};
	Chat{IsService(true); Reference("Chat");
		Name              : string = "Chat";
		BubbleChatEnabled : bool   = false;
		LoadDefaultChat   : bool   = false;
	};
	HttpService{IsService(true); Reference("HttpService");
		Name        : string = "HttpService";
		HttpEnabled : bool   = true;
	};
	InsertService{IsService(true); Reference("InsertService");
		Name                    : string = "InsertService";
		AllowClientInsertModels : bool   = false;
		AllowInsertFreeModels   : bool   = false;
	};
	StarterPlayer{IsService(true); Reference("StarterPlayer");
		Name                    : string = "StarterPlayer";
		AllowCustomAnimations   : bool   = false;
		EnableMouseLockOption   : bool   = false;
		LoadCharacterAppearance : bool   = false;
		UserEmotesEnabled       : bool   = false;
		StarterCharacterScripts{Reference("StarterCharacterScripts");
			Name : string = "StarterCharacterScripts";
			BoolValue{ Reference("Sound");
				Name  : string = "Sound";
				Value : bool   = false;
			};
		};
		StarterPlayerScripts{Reference("StarterPlayerScripts");
			Name : string = "StarterPlayerScripts";
			BoolValue{ Reference("PlayerScriptsLoader");
				Name  : string = "PlayerScriptsLoader";
				Value : bool   = false;
			};
			BoolValue{ Reference("PlayerModule");
				Name  : string = "PlayerModule";
				Value : bool   = false;
			};
		};
	};
	LocalizationService{IsService(true); Reference("LocalizationService");
		Name : string = "LocalizationService";
	};
	DataStoreService{IsService(true); Reference("DataStoreService");
		Name           : string = "DataStoreService";
		AutomaticRetry : bool   = false;
	};
]]}
