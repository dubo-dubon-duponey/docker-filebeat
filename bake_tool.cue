package bake

command: {
  image: #Dubo & {
    args: {
      BUILD_TITLE: "Filebeat"
      BUILD_DESCRIPTION: "A dubo image for Filebeat based on \(args.DEBOOTSTRAP_SUITE) (\(args.DEBOOTSTRAP_DATE))"
    }
  }
}
