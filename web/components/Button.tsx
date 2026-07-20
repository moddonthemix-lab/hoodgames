import type { ButtonHTMLAttributes } from "react";
import clsx from "clsx";

type Variant = "primary" | "danger" | "ghost";

export function Button({
  variant = "primary",
  className,
  disabled,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  return (
    <button
      disabled={disabled}
      className={clsx(
        "w-full rounded-lg px-4 py-3 text-sm font-bold uppercase tracking-wide transition-colors disabled:cursor-not-allowed disabled:opacity-40",
        variant === "primary" && "bg-accent text-white hover:bg-accent-hover",
        variant === "danger" && "bg-loss text-white hover:brightness-110",
        variant === "ghost" && "border border-bg-border bg-bg-raised text-ink hover:border-accent",
        className
      )}
      {...props}
    />
  );
}
