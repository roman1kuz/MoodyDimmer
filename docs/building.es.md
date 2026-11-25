[English](building.md) | [Русский](building.ru.md) | [Español](building.es.md)

# Compilación

## Compilar e instalar

Para compilar bastan las Command Line Tools. Con Xcode instalado, el icono de la app se compila en el nuevo formato
de Icon Composer.

```sh
./scripts/make-cert.sh             # una vez: certificado local de firma de código
./scripts/build-app.sh --install   # compilar, copiar a /Applications y reabrir
```

Cada compilación genera `build/MoodyDimmer-<versión>.dmg` (la app y un acceso directo a Aplicaciones). Sin
`--install` solo se crea el DMG. El `.app` se monta en una carpeta temporal que luego se borra, así que macOS ve un
único Moody Dimmer: el de /Applications.

## Firma de código y acceso de Accesibilidad

`scripts/make-cert.sh` crea un certificado autofirmado, *Moody Dimmer Local Signing*, en el llavero de inicio de
sesión. El script de compilación firma con él, así que la firma no cambia entre compilaciones y macOS conserva el
acceso de Accesibilidad.

Sin el certificado la app se firma ad hoc y el acceso se pierde tras cada compilación: quita Moody Dimmer de *Ajustes
del Sistema → Privacidad y seguridad → Accesibilidad* y vuelve a darle acceso.

En la primera firma, macOS puede preguntar si `codesign` puede usar la clave. Elige *Permitir siempre* para que no
vuelva a preguntar; hasta que respondas, la compilación espera.

## Icono de la app

El icono de la app (oscuro) se genera desde código. Después de editar `scripts/make-icon.swift`, vuelve a generarlo:

```sh
swift scripts/make-icon.swift "$PWD"                                 # → Resources/AppIcon.icon y AppIcon.icns
swift scripts/make-icon.swift "$PWD" --preview "$PWD/Design/AppIcon"  # vistas previas de todas las variantes
```

El generador conserva varias variantes (cascade, veil, dimmer), cada una en tema claro y oscuro. Sus vistas previas
están en `Design/AppIcon`.

El icono que se distribuye, `Resources/AppIcon.icon`, sigue las pautas de macOS 27: capas vectoriales cuadradas (la
ventana trasera oscurecida y la delantera iluminada) sobre un relleno en degradado, sin sombras, brillos ni texturas
integrados. macOS añade Liquid Glass y genera las versiones transparente y tintada. La compilación lo procesa con
`actool` de Xcode; sin Xcode usa `AppIcon.icns` (la representación del sistema del mismo icono).
