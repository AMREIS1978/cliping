# ClipWatch

MVP Android/iOS em Flutter para clipping diário por nome, empresa ou expressão.

## O que já faz
- Adicionar vários nomes/expressões a monitorizar.
- Guardar as monitorizações no dispositivo.
- Pesquisar notícias portuguesas através da FreeNewsAPI.
- Atualizar manualmente a lista.
- Abrir a notícia no jornal original.
- Executar verificação periódica em background no Android através de WorkManager.
- Enviar notificação quando encontra novas referências.
- Projeto preparado para GitHub Actions gerar o APK automaticamente.

## Atualizações sem desinstalar
Mantenha sempre o mesmo `applicationId`/package e a mesma chave de assinatura. Aumente a versão em `pubspec.yaml`, por exemplo:

`version: 1.0.1+2`

O número depois de `+` tem de subir em cada build publicado.

## GitHub
1. Abra a aba **Actions**.
2. Execute **Build Android APK** ou faça um novo push.
3. No final, descarregue o artifact **ClipWatch-Android**.

## Nota de arquitetura
Para clipping diário realmente fiável, mesmo que o utilizador force a paragem da app, a evolução recomendada é mover o agendamento para um backend e usar push notifications. Esta primeira versão usa o scheduler nativo do Android.
