[English](how-it-works.md) | [Русский](how-it-works.ru.md) | [Español](how-it-works.es.md)

# Cómo funciona

## La superposición

- Cada pantalla tiene una ventana superpuesta transparente que deja pasar los clics. Se coloca justo debajo de la
  ventana que sigue iluminada (`NSWindow.order(.below, relativeTo:)`): todo lo que está por encima queda iluminado y
  todo lo que está por debajo recibe el efecto.
- Con varias pantallas cada una tiene su propia ventana iluminada: la ventana activa en su pantalla y, en las demás,
  la ventana superior que está mayormente en ella. Cada superposición se coloca bajo la ventana de su pantalla, y la
  lista de ventanas se lee una sola vez para todas.
- En el modo *Todas las ventanas de la app*, la superposición tiene huecos recortados para las demás ventanas de la
  app (una máscara `CAShapeLayer`). Una ventana de otra app que quede sobre una de ellas (entre las ventanas de la
  app) también recibe un hueco, en toda su parte visible, para que no parezca un parche oscuro sobre las ventanas
  iluminadas.
- Al cambiar el foco, la superposición no se sustituye ni se desvanece entera: solo se anima su máscara, en las zonas
  de las ventanas que se iluminan u oscurecen. El resto de la pantalla mantiene exactamente el mismo oscurecimiento y
  desenfoque todo el tiempo.
- Antes de colocar la superposición bajo una ventana, la app comprueba que esa ventana sigue en pantalla. Colocarla
  bajo una ventana que ya no existe la dejaría debajo de todas las ventanas.
- *Iluminar la ventana bajo el puntero* coloca la superposición debajo de la ventana bajo el puntero, así que ella y
  todas las ventanas que tiene encima se iluminan; la ida y la vuelta usan la misma animación de la máscara que un
  cambio de foco. Los 1,5 segundos cuentan mientras el puntero sigue sobre ventanas de la misma app, porque muchas
  apps dibujan una ventana como varias. Con el efecto ya bajado, pasar a otra ventana se aplica tras 0,3 s, para que
  cruzar huecos y ventanas de fondo por el camino no cuente. Al buscar la ventana bajo el puntero se ignoran las
  ventanas flotantes de otras apps en otros niveles (como el panel casi transparente de una utilidad para la muesca);
  solo la interfaz de macOS, como el Dock y la barra de menús, lo impide. El puntero se compara con la zona iluminada
  y con una lista en caché de los marcos de las ventanas; la lista de ventanas solo se lee cuando el puntero entra en
  una zona oscurecida, unas pocas veces por segundo como mucho mientras se mueve por ella, y cuando termina una
  espera.

## Seguimiento del foco

- Todo funciona por eventos: notificaciones de `NSWorkspace`, un `AXObserver` sobre la app activa y las
  notificaciones de ventanas de WindowServer. Sin temporizadores de sondeo. Detalles y mediciones:
  [performance.es.md](performance.es.md).
- El cierre de una ventana se detecta al instante mediante Accesibilidad, así que el efecto pasa a la siguiente
  ventana durante la animación de cierre, no después.
- Cuando la app activa no tiene ventanas, sigue iluminada la ventana superior de la pantalla. Cuando una app recién
  abierta muestra su primera ventana antes de responder a Accesibilidad, la detectan los eventos de ventanas de
  WindowServer.

## Cuándo se aparta el efecto

- Spaces a pantalla completa (vídeo, reproductores, apps a pantalla completa): la superposición usa el comportamiento
  de colección `.fullScreenNone`, así que el propio WindowServer la mantiene fuera de esos Spaces, incluso durante la
  animación de transición. Al cambiar de Space, la app también comprueba una vez el tipo de Space de cada pantalla
  para no recolocar ahí la superposición. Para ello usa funciones privadas de SkyLight cargadas con `dlsym`, con
  `AXFullScreen` como alternativa. Las ventanas sin bordes que cubren toda la pantalla (juegos) se detectan por su
  tamaño.
- Mission Control, App Exposé y Mostrar escritorio: se detectan por la ventana de WindowManager que cubre la pantalla
  en estos modos (ver [performance.es.md](performance.es.md)).
- Arrastrar: cuando lo arrastrado sale de las ventanas de la app de origen (*Quitar el efecto al arrastrar*).
- Capturas (*Ocultar en capturas de pantalla*): las ventanas superpuestas tienen `sharingType = .none`, así que
  WindowServer las deja fuera de las imágenes capturadas mientras siguen en pantalla. Mientras está abierta la interfaz
  de captura (⌘⇧4, ⌘⇧5), el proceso `screencapture` muestra una ventana `touchshield` (capa 1498) sobre la pantalla, y
  el efecto se aparta mientras está ahí (ver [performance.es.md](performance.es.md)).

## Efectos

- El desenfoque es una `NSVisualEffectView`; su radio se ajusta en la `CABackdropLayer` interna. Se oculta por
  completo cuando no se usa.
- Oscurecer es una capa negra; el grano es una textura de ruido generada una sola vez y repetida en mosaico.

## Respuesta háptica

Los toques controlan directamente el actuador Force Touch del trackpad mediante funciones privadas de
MultitouchSupport cargadas con `dlsym` (como hace HapticKey): a diferencia de `NSHapticFeedbackManager`, su
intensidad puede variar y funcionan con la respuesta háptica del sistema desactivada. El actuador se abre con el
primer toque y se cierra tras 3 segundos sin toques. Si alguna vez faltan esas funciones, la app recurre a
`NSHapticFeedbackManager`. Si la entrada viene de un trackpad se sabe por el propio evento (su subtipo touch; al
desplazar, su fase de gesto).

## Solución de problemas

Si a veces el efecto no funciona, revisa el registro:

```sh
log stream --debug --style compact --predicate 'subsystem == "io.github.roman1kuz.moodydimmer"'
```

La línea `accessibility not trusted` significa que se perdió el acceso de Accesibilidad (normalmente tras compilar
sin el certificado de firma, ver [building.es.md](building.es.md)).

## Limitaciones

- El radio de las esquinas de los huecos es aproximado (`FocusTracker.holeCornerRadius`).
- El radio del desenfoque se ajusta a través de la `CABackdropLayer` interna de `NSVisualEffectView` (el filtro
  `gaussianBlur`). Esta estructura no está documentada. Si una futura versión de macOS la cambia, la app pasa sola a
  ajustar la intensidad del desenfoque mediante la opacidad de la capa.
- En el modo *Solo la ventana activa*, los paneles flotantes y menús en niveles de ventana no estándar pueden quedar
  bajo el efecto.
- Usarla a la vez que Monocle o HazeOver genera conflictos: ambas apps colocan su superposición bajo la misma ventana.
