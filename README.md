# Test

Projeto Roblox sincronizado com o Roblox Studio via [Rojo](https://rojo.space).

## Conectar ao Roblox Studio

1. Instale o [Rokit](https://github.com/rojo-rbx/rokit) e, na pasta do projeto, rode:
   ```sh
   rokit install
   ```
   (Isso instala a versão do Rojo definida em `rokit.toml`.)
2. No Roblox Studio, instale o plugin do Rojo:
   ```sh
   rojo plugin install
   ```
   Ou pela [Creator Store](https://create.roblox.com/store/asset/13916111004/Rojo).
3. Inicie o servidor do Rojo:
   ```sh
   rojo serve
   ```
4. No Studio, abra um place, clique no botão **Rojo** na aba *Plugins* e depois em **Connect**
   (padrão: `localhost:34872`).

Pronto — alterações nos arquivos em `src/` aparecem no Studio em tempo real.

## Estrutura

| Pasta         | Destino no Studio                                   |
|---------------|-----------------------------------------------------|
| `src/shared`  | `ReplicatedStorage.Shared`                          |
| `src/server`  | `ServerScriptService.Server`                        |
| `src/client`  | `StarterPlayer.StarterPlayerScripts.Client`         |

## Gerar um arquivo de place

```sh
rojo build -o Test.rbxl
```
