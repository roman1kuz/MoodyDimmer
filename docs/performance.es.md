[English](performance.md) | [Русский](performance.ru.md) | [Español](performance.es.md)

# Rendimiento y energía

Moody Dimmer está pensado para no costar casi nada mientras funciona. Esta nota recoge cómo la app mantiene bajo su
coste y qué se ha medido. La app no hace sondeos: todo reacciona a eventos.

## Mediciones

Medido en macOS 27.2 (Apple Silicon) con `top -stats cpu,idlew,power`, los mismos datos que muestra el Monitor de
Actividad. Muestras de 5 s, con la app en reposo en segundo plano y el efecto de oscurecer activado. Las cifras varían
de una muestra a otra y entre Macs, así que son aproximadas, no garantías.

| Estado | CPU | Activaciones en reposo cada 5 s | Impacto energético |
|---|---|---|---|
| Efecto activado | ~0 % | ~1–3 | ~0 |
| Efecto desactivado | ~0 % | ~2 | ~0 |
| Cambiar de ventana con un clic cada 0,4 s (oscurecer + desenfoque) | ~1 % | — | ~1 |
| Puntero en movimiento continuo, 120 movimientos/s (efecto activado) | ~1,5 % | ~2 | ~1,5 |

La app no tiene temporizadores propios; las ~2 activaciones restantes son, muy probablemente, tareas internas de
AppKit. Mientras el puntero se mueve, la app recibe cada movimiento del ratón para la función de agitar el puntero;
deja de costar nada en cuanto el puntero se detiene, y al desactivar esa función el coste desaparece por completo.
Los movimientos llegan por un `CGEventTap` de solo lectura. El análisis de cada movimiento son un par de
comparaciones; casi todo el coste está en despertar para recibir el evento, por lo que crece con la frecuencia de
eventos del puntero (hasta 120 movimientos/s en una pantalla ProMotion).

Como referencia, en muestras de 3 s Finder tuvo ~160 activaciones en reposo, Dock ~230 y WindowManager ~400. Una
pestaña de navegador típica tiene un impacto energético de unidades o decenas.

Memoria física: ~15 MB (`footprint`).

## Qué funciona por eventos

Todo reacciona a eventos y no hace nada entre ellos:

- Seguimiento del foco: notificaciones de `NSWorkspace` (activación, cierre y ocultación de apps, cambios de Space,
  reactivación) y un `AXObserver` sobre la app activa (cambio de ventana principal y con foco, ventana creada,
  destruida, movida, redimensionada). Las ráfagas de eventos, como al arrastrar una ventana, se agrupan en una sola
  actualización por pasada del bucle de eventos.
- Sin ventana activa (se cerró su última ventana): sigue iluminada la ventana superior de la pantalla. Las ventanas
  de otras apps pueden cambiar entonces sin ninguna activación ni evento AX, así que la actualización la disparan los
  eventos de WindowServer de ventana mostrada / destruida (`1325`/`1326`, ver más abajo). Lo mismo ocurre mientras
  una app recién abierta aún no tiene ventana: su primera ventana puede aparecer antes de que la app responda a AX,
  así que ningún evento AX la anuncia. El resto del tiempo estos eventos se ignoran, salvo la destrucción de la
  ventana iluminada, que dispara una actualización de inmediato.
- Algunos eventos van seguidos de comprobaciones puntuales breves (a los 0,12 s y 0,4 s), porque WindowServer sube
  las ventanas un poco después de que lleguen los eventos. Solo se ejecutan tras un evento, nunca en segundo plano.
- Los clics y arrastres del ratón (Quitar el efecto al arrastrar) usan monitores de eventos globales; el gesto de
  agitar, un event tap de solo lectura. Cada evento del ratón cuesta un par de comparaciones.
- El atajo de teclado usa la API de hotkeys de Carbon: el sistema llama a la app solo al pulsar las teclas.
- La superposición son capas estáticas de Core Animation que compone WindowServer. La textura del grano se genera una
  sola vez. En reposo no se anima nada.
- La animación del interruptor del menú usa un temporizador solo durante sus 0,2 s.

## Mission Control, App Exposé, Mostrar escritorio

En estos modos se quita el efecto. macOS 27 no tiene ninguna notificación pública para ellos. Se comprobó lo siguiente:

- Las notificaciones AX de Exposé del Dock (`AXExposeShowAllWindows`, `AXExposeShowFrontWindows`,
  `AXExposeShowDesktop`, `AXExposeExit`). La suscripción funciona, pero no llega nada: el Dock ya no dibuja estos
  modos.
- WindowManager, que es quien los dibuja ahora, rechaza las notificaciones AX (`kAXErrorNotificationUnsupported`),
  incluidas las estándar, como ventana creada.
- No se publica ninguna notificación de `NSWorkspace` ni distribuida.
- El estado de oclusión de la ventana superpuesta no cambia.

Lo que sí se ve es una ventana de WindowManager sobre toda la pantalla: `ExposeShieldWindow` (capa 19) en Mission
Control y App Exposé, `ShowDesktopOverlay` (capa 18) en Mostrar escritorio. Los títulos de las ventanas de otras
apps requieren acceso de Grabación de pantalla, así que la ventana se identifica por propietario, capa y tamaño de
pantalla completa.

Para saber cuándo aparece esa ventana sin sondear, `SystemModeWatcher` usa las propias notificaciones de WindowServer
(SkyLight, API privada, cargada con `dlsym`). Al registrarse en todos los tipos de evento del 0 al 2000 y abrir los
modos, se vio que WindowServer está en silencio en reposo y publica:

- `1325` cuando una ventana se hace visible, con el número de ventana en los datos (`[UInt32 flags, 0, window]`).
  Se dispara para las ventanas escudo al abrirse un modo y, de vez en cuando, para ventanas de otras apps.
- `1326` cuando una ventana se destruye (el escudo, al cerrarse el modo). Una ventana que solo se retira de la
  pantalla o se minimiza no publica nada.
- Los cambios de app no publican ninguno de los dos.

Así que el observador se registra solo en `1325` y `1326`. Con `1325` consulta esa única ventana y la recuerda si es
un escudo; con `1326` la olvida. Mientras un modo está abierto, un clic del ratón vuelve a comprobar que el escudo
sigue en pantalla, por si se perdió algún evento.

Si `SLSRegisterNotifyProc` desaparece en una futura versión de macOS, el observador recurre al sondeo: comprueba los
números de las ventanas en pantalla 5 veces por segundo (`CGWindowListCreate`, ~70 µs por llamada) y solo pide sus
descripciones cuando ese conjunto cambia. Eso cuesta ~0,2–0,4 % de CPU y ~14 activaciones cada 5 s con el efecto
activado.

## Qué es lo que más cuesta

El desenfoque. WindowServer lo compone en la GPU y lo recalcula cuando cambia el contenido de debajo. Oscurecer y el
grano son capas estáticas y no cuestan casi nada.

## Cómo medir

```sh
P=$(pgrep -x MoodyDimmer)
top -l 6 -s 5 -pid $P -stats pid,command,cpu,idlew,power   # CPU, activaciones en reposo, impacto energético
footprint $P | grep phys_footprint                          # memoria
sample $P 5                                                 # en qué se va el tiempo
```
