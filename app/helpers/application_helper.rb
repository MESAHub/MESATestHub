module ApplicationHelper
  # Inline the MESA M-mark as an SVG element so it inherits color from
  # its parent (Tailwind's text-* utilities, e.g. `text-brand`). Using
  # `image_tag "mesa-mark.svg"` would render an `<img>` whose fill is
  # baked at request time and ignores `currentColor`.
  def mesa_mark(class_names: nil, **attrs)
    attrs[:class] = class_names if class_names
    attrs[:viewBox] = "0 0 135 115"
    attrs[:xmlns] = "http://www.w3.org/2000/svg"
    attrs["aria-label"] ||= attrs[:aria_label] || "MESA mark"
    attrs.delete(:aria_label)
    content_tag(:svg, attrs) do
      tag.path(
        fill: "currentColor",
        d: "M68.44,81.95L102.61,7.84l26.51,99.66h-17.63v-.95l1.7-1.7c.23-.23.42-.54.58-.95.16-.41.24-.84.24-1.29,0-.23-.05-.57-.14-1.02-.09-.45-.23-.97-.41-1.56l-14.71-56.68-30.98,67.32L35.42,44.05l-13.49,55.93c-.14.5-.24.95-.3,1.36-.07.41-.1.79-.1,1.15,0,.5.07.95.2,1.36.14.41.34.75.61,1.02l1.56,1.7v.95H6.4L33.32,7.84l35.12,74.1Z"
      )
    end
  end
end
