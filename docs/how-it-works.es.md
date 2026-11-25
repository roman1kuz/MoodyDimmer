[English](how-it-works.md) | [Русский](how-it-works.ru.md) | [Español](how-it-works.es.md)

# Cómo funciona

## La superposición

- Cada pantalla tiene una ventana superpuesta transparente que deja pasar los clics. Se coloca justo debajo de la
  ventana que sigue iluminada (`NSWindow.order(.below, relativeTo:)`): todo lo que está por encima queda iluminado y
  todo lo que está por debajo recibe el efecto.
- En el modo *Todas las ventanas de la app*, la superposición tiene huecos recortados para las demás ventanas de la
  app (una máscara `CAShapeLayer`). A los huecos se les restan las zonas tapadas por ventanas de otras apps.
- Al cambiar el foco, la superposición no se sustituye ni se desvanece entera: solo se anima su máscara, en las zonas
  de las ventanas que se iluminan u oscurecen. El resto de la pantalla mantiene exactamente el mismo oscurecimiento y
  desenfoque todo el tiempo.
- Antes de colocar la superposición bajo una ventana, la app comprueba que esa ventana sigue en pantalla. Colocarla
  bajo una ventana que ya no existe la dejaría debajo de todas las ventanas.

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

## Efectos

- El desenfoque es una `NSVisualEffectView`; su radio se ajusta en la `CABackdropLayer` interna. Se oculta por
  completo cuando no se usa.
- Oscurecer es una capa negra; el grano es una textura de ruido generada una sola vez y repetida en mosaico.

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
