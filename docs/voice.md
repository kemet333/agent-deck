# Agent Bar / Agent Deck · voz propia

Agent Bar es el nombre usado en la cartera de Prompted. La implementación existente vive en `kemet333/agent-deck`, como Agent Deck. Esta ampliación conserva esa app, su bundle ID, barra/orbe, teclas, JSON y URL scheme.

## Recorrido integrado

1. Configurar la clave de OpenAI en Voz → Ajustes. Se guarda en el Llavero del Mac; nunca en JSON, historial ni URLs. La interfaz no muestra una clave guardada y no comprueba acceso mediante llamadas de pago en segundo plano.
2. Colocar el cursor en el campo de destino. Mantener Fn, hablar y soltar. Cada dictado admite hasta tres minutos. Doble toque o Fn+Control dejan el micrófono en manos libres; otro Fn termina. Fn+Opción edita una selección explícita. Escape cancela grabación/procesamiento.
3. OpenAI transcribe y, salvo modo Literal, procesa el texto con el tono elegido. La API y los modelos requieren acceso y saldo propios. No hay integración con una sesión del navegador de ChatGPT.
4. Pegar automáticamente, o conservar como borrador. Intro es opcional y está desactivado por defecto. Para voz, no se pulsa Intro si no se puede verificar la inserción en el campo original. Los terminales/editores conocidos tienen protección configurable; esa lista no detecta todos los terminales integrados ni todos los contextos de una app.
5. Si el destino cambia, conservar el borrador. Desde la ventana Voz, volver al campo original y usar la flecha de la barra no activante. La ventana de ajustes no pega en segundo plano. Los textos recuperados tras reiniciar o importados no conservan un destino: se copian y pegan manualmente. Copiar y exportar son alternativas explícitas.

La protección de conflictos evita capturar Fn si Vowen está abierto. Si ya se ha desactivado Fn en Vowen, se puede desactivar esta protección. Agent Deck no modifica Vowen, el teclado del sistema ni sus permisos.

## Funciones reales y límites

| Función de referencia | Estado en esta entrega |
| --- | --- |
| Fn mantener/soltar, doble toque y manos libres | Implementados con tap nativo y máquina de gestos; requieren Accesibilidad. Pendiente prueba manual con teclado real. |
| Micrófono y transcripción OpenAI | Código integrado, grabación AAC temporal, cliente HTTP, cancelación y recuperación; pruebas sintéticas. API real pendiente de clave del propietario. |
| Motor Apple | Se conserva; exige reconocimiento en dispositivo disponible. No usa un servicio Apple cloud como alternativa silenciosa. |
| Limpieza, tono y estilo personalizado | Implementados mediante Responses API. Tono global o por bundle ID de app. Literal omite esa petición. |
| Vocabulario y expansiones | Pistas de vocabulario y sustituciones literales de una pasada; no ejecutan comandos. |
| Edición por voz de selección | Fn+Opción, selección capturada explícitamente y validada antes de insertar. Sin herramientas de sistema/shell generadas por el modelo. |
| Pegar / inserción directa | Implementados; destino verificado y portapapeles restaurado solo si sigue siendo propiedad de la inserción. |
| Historial y borrador | Últimos 100 textos locales, borrador recuperable tras reinicio, copiar/exportar y borrado con confirmación. Nunca se reinserta automáticamente un borrador recuperado. |
| Archivos de audio/vídeo | Importación explícita de archivos locales originales MP3/MP4/MPEG/MPGA/M4A/WAV/WebM hasta 25 MB; enlaces y archivos especiales se rechazan, y la lectura se limita por los bytes reales. Sin conversión universal ni descargas de enlaces. |
| Resúmenes | Resúmenes de transcripciones guardadas/importadas; no inventan una grabación de reunión. |
| Reuniones con audio del sistema y micrófono | Pendiente. No se anuncia como implementado por disponer de resumen de archivo. |
| Identificación/renombrado de interlocutores | Pendiente. |
| Pre-reads, calendario y detección de llamadas | Pendiente de integración propia y permisos. |
| Ask sobre reuniones, conectores, webhooks y sincronización cloud | Pendientes. No se envían notas ni se ejecutan webhooks en esta entrega. |
| Vowen Nano/local AI, modelos offline propios y Windows | Pendientes; esta app existente es macOS/Apple Silicon. |

La referencia es funcional, con código propio; no se redistribuye el programa ni los modelos de Vowen. Esta entrega no acredita paridad completa con Vowen.

## Persistencia y recuperación

- Se preserva `keys.json` y el espacio existente de Agent Deck. Los nuevos archivos son `voice-settings.json`, `voice-history.json` y `voice-draft.json`, con permisos de usuario (0600).
- El historial contiene texto, fecha, origen y tipo, sin clave ni audio. Desactivar historial impide nuevos registros; no borra los existentes. El borrador pendiente se guarda aparte para recuperación.
- El audio del modo OpenAI se graba en un directorio temporal privado. Se elimina al detener o cancelar. El audio preparado para reintento se conserva solo en memoria y no sobrevive al cierre. Una interrupción del proceso antes de la limpieza puede dejar un temporal del sistema; no se promete borrado seguro frente a un fallo del sistema.
- OpenAI recibe el audio seleccionado/dictado; para limpieza/edición recibe el texto y, en modo edición, la selección explícita. Las peticiones Responses usan `store: false`; eso no sustituye las condiciones de tratamiento del proveedor.
- Una petición cancelada no puede entregar después su resultado a otra sesión. Los fallos de Llavero no cambian la fase de una grabación y los atajos no descartan borradores inactivos.

## Verificación reproducible

`zsh test.sh` usa HTTP, grabador, permisos, credenciales e inserción falsos. No lee una clave del propietario, no graba, no pega en sus apps ni hace peticiones reales. Incluye gestos, cancelaciones, permiso pendiente, multipart, Responses, errores, persistencia y recuperaciones.

`zsh Tests/build-preview.sh` crea una app separada de revisión visual, con textos sintéticos, almacenamiento temporal, sin AppDelegate de producción ni tap, credenciales reales o grabación. No es la app comercial ni sustituye una prueba real de Fn.

Fuentes consultadas el 2 de noviembre de 2026:

- [OpenAI · transcripción](https://developers.openai.com/api/docs/guides/speech-to-text)
- [OpenAI · Responses / texto](https://developers.openai.com/api/docs/guides/text?api-mode=responses)
- [Vowen · atajos](https://docs.vowen.ai/features/shortcuts)
- [Vowen · inserción](https://docs.vowen.ai/features/text-insertion)
- [Vowen · comparación de funciones](https://vowen.ai/pricing/)
